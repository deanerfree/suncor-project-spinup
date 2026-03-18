#!/usr/bin/env python3
"""
Extract named sections from Suncor well stick diagram PDFs.

Usage:
    python3 extract_pdf_data.py <pdf_path> [section1] [section2] ...

    Available sections:
        "Geological Formation Information"
        "Drilling Notes"
        "Logging Information"
        "Casing Design"

    If no sections are specified, all known sections are extracted.

Output: JSON array (one entry per page) to stdout, errors to stderr.

Architecture
------------
Each section is defined by:
  - A multi-word header sequence used to locate it on the page
  - An x-column hint (LEFT / RIGHT / auto-detect from same-row neighbors)

Section bounding boxes are computed dynamically:
  - y_top  : the detected header row's top coordinate
  - y_bottom: the next header that overlaps the same x-range, or page bottom
  - x_lo/hi: for single-column headers → fixed column bands;
             for multi-column rows (same y) → midpoints between adjacent anchors

Geological Formation Information is additionally parsed into structured rows
(the 5-column table). All other sections are returned as raw text.
"""

import sys
import json
import re
import pdfplumber

# ── Constants ─────────────────────────────────────────────────────────────────

ROW_TOLERANCE   = 3.0   # pt: words within this vertical distance = same row
SAME_LINE_TOL   = 4.0   # pt: headers within this vertical distance = same row

# Column bands for single-column sections
RIGHT_COL_X_LO  = 250   # main right column starts here
PAGE_X_HI       = 612   # page right edge

# Sections whose headers sit in the right column but whose table content
# spans the full page width. Explicitly listed to avoid wellbore diagram
# depth labels (e.g. "SCU 262.2mKB") bleeding into adjacent sections.
FULL_WIDTH_SECTIONS = {
    "Drilling Fluids",
    "Cementing",
}

# Each entry:  (canonical_name, [first_word, second_word, ...])
# The section is anchored to the x0 of the first matching word.
SECTION_REGISTRY = [
    ("Geological Formation Information", [["Geological", "Formation", "Information"]]),
    ("Surface Location Information",     [["Surface",    "Location",  "Information"]]),
    ("General Information",              [["General",    "Information"]]),
    ("Drilling Notes",                   [["Drilling",   "Notes"]]),
    ("Casing Accessories",               [["Casing",     "Accessories"]]),
    ("Drilling Fluids",                  [["Drilling",   "Fluids"]]),
    ("Cementing",                        [["Cementing"]]),
    # "Cutting" (space-separated) or "Cutting/Coring" (slash-joined, no spaces)
    ("Drill Cutting / Coring Information", [
    ["Drill", "Cutting"],
    ["Drill", "Cutting/Coring"],
    ]),
    ("Casing Design",                    [["Casing",     "Design"]]),
    ("Piezometer Design",                [["Piezometer", "Design"]]),
    ("Logging Information",              [["Logging",    "Information"]]),
    ("Thermocouple Design",              [["Thermocouple", "Design"]]),
]

# Sections we can parse into structured data (beyond raw text)
STRUCTURED_SECTIONS = {"Geological Formation Information", "Logging Information", "Drilling Fluids", "Casing Design", "Surface Location Information"}

# Column header sequences used for the geological formation table
GEO_COL_SEQUENCES = [
    ("formation",                   ["Geological", "Formation"]),
    ("masl_tvd",                    ["masl", "TVD"]),
    ("mkb_tvd",                     ["mKB",  "TVD"]),
    ("pressure_kpa",                ["kPa"]),
    ("emw_kg_m3",                   ["kg/m3"]),
    ("potential_drilling_problems", ["Potential", "Drilling", "Problems"]),
]

FORMATION_RIGHT_MARGIN = 8  # pt: formation col right edge = masl_anchor - this


# ── Utilities ─────────────────────────────────────────────────────────────────

def build_line_index(words):
    """round(top) → words sorted by x0."""
    lines = {}
    for w in words:
        key = round(w["top"], 1)
        lines.setdefault(key, []).append(w)
    return {k: sorted(v, key=lambda x: x["x0"]) for k, v in lines.items()}


def sequence_starts_at(word_list, seq, idx):
    for j, s in enumerate(seq):
        if idx + j >= len(word_list) or word_list[idx + j]["text"] != s:
            return False
    return True


def group_words_into_rows(words):
    if not words:
        return []
    sw = sorted(words, key=lambda w: (w["top"], w["x0"]))
    rows, current, cur_top = [], [], sw[0]["top"]
    for w in sw:
        if abs(w["top"] - cur_top) <= ROW_TOLERANCE:
            current.append(w)
        else:
            rows.append(current)
            current, cur_top = [w], w["top"]
    if current:
        rows.append(current)
    return rows


def parse_float_or_none(s):
    if not s:
        return None
    try:
        return float(s.replace(",", ""))
    except ValueError:
        return None


# ── Section detection ─────────────────────────────────────────────────────────

class SectionAnchor:
    """A detected section header with its page coordinates."""
    def __init__(self, name, x0, x1, top):
        self.name = name
        self.x0   = x0    # left edge of first header word
        self.x1   = x1    # right edge of last header word
        self.top  = top   # y coordinate of header row
        # Filled in by compute_bounds():
        self.x_lo   = None
        self.x_hi   = None
        self.y_top  = None
        self.y_bot  = None

    def __repr__(self):
        return (f"SectionAnchor({self.name!r}, x={self.x_lo:.0f}-{self.x_hi:.0f}, "
                f"y={self.y_top:.0f}-{self.y_bot:.0f})")


def detect_section_anchors(words):
    """
    Scan every line for known section header sequences.
    Returns list of SectionAnchor (unsorted).
    """
    lines = build_line_index(words)
    found = []

    for top_key, line_words in sorted(lines.items()):
        for name, sequences in SECTION_REGISTRY:       # sequences is now a list of alternatives
            for seq in sequences:                       # try each alternative in order
                for i, w in enumerate(line_words):
                    if w["text"] == seq[0] and sequence_starts_at(line_words, seq, i):
                        last_word = line_words[i + len(seq) - 1]
                        found.append(SectionAnchor(name, w["x0"], last_word["x1"], top_key))
                        break   # don't double-match on the same line
                else:
                    continue    # this seq didn't match — try the next alternative
                break           # a seq matched; skip remaining alternatives for this name

    return found


def compute_bounds(anchors, page_height, words=None):
    """
    For each anchor, compute (x_lo, x_hi, y_top, y_bot).

    Headers on the same y-row (within SAME_LINE_TOL) are treated as
    side-by-side columns; their x boundaries are midpoints between anchors.
    Headers alone on their row get a column-based x default, then are widened
    to full-page if their content extends into the left column (content-peek).
    """
    # Group anchors that share a y-row
    rows = []
    used = set()
    for a in sorted(anchors, key=lambda x: x.top):
        if id(a) in used:
            continue
        row = [a]
        used.add(id(a))
        for b in anchors:
            if id(b) not in used and abs(b.top - a.top) <= SAME_LINE_TOL:
                row.append(b)
                used.add(id(b))
        rows.append(sorted(row, key=lambda x: x.x0))

    # Assign x bounds within each row.
    #
    # For the FIRST section in a multi-column row (or a solo section), x_lo is
    # the page/column edge. For all SUBSEQUENT sections, x_lo is set to
    # (header_x0 - COLUMN_MARGIN) rather than the midpoint between neighbors.
    # This prevents text wrapping from an adjacent column from bleeding in —
    # wrapped lines always restart near their column's left margin, which is
    # well to the left of the next column's header.
    COLUMN_MARGIN = 8  # pt
    for row in rows:
        if len(row) == 1:
            a = row[0]
            if a.x0 < RIGHT_COL_X_LO:
                a.x_lo, a.x_hi = 0, RIGHT_COL_X_LO
            elif a.x0 > 400:
                # Header is far right (e.g. Thermocouple Design at x~482).
                # Using the full right-column band (x=250) would pull in adjacent
                # section content. Anchor tightly to the header instead.
                a.x_lo, a.x_hi = a.x0 - COLUMN_MARGIN, PAGE_X_HI
            else:
                a.x_lo, a.x_hi = RIGHT_COL_X_LO, PAGE_X_HI
        else:
            for i, a in enumerate(row):
                if i == 0:
                    a.x_lo = 0
                elif i == len(row) - 1:
                    # Last column: use the previous column's x_hi as our x_lo.
                    a.x_lo = row[i - 1].x_hi
                else:
                    # Middle column: midpoint between the previous header's right
                    # edge and this header's left edge — symmetric with how x_hi
                    # is computed. This captures row labels (e.g. "Hole Size (mm)")
                    # that sit in the inter-column gap left of the header anchor.
                    a.x_lo = (row[i - 1].x1 + a.x0) / 2

                # x_hi: page edge for the last column; otherwise the midpoint
                # between this header's RIGHT edge and the next header's LEFT
                # edge. This places the boundary safely in the inter-column gap,
                # so Piezometer content (which starts left of its header) does
                # not bleed into the Casing Design column.
                if i == len(row) - 1:
                    a.x_hi = PAGE_X_HI
                else:
                    a.x_hi = (a.x1 + row[i + 1].x0) / 2

    # Solo far-right sections (e.g. Thermocouple Design, x0>400): set x_lo
    # to the x_hi of the nearest section that sits to their left.
    # Must be done BEFORE the y_bot loop so that adjacency checks see the
    # correct x_lo (e.g. Thermocouple x_lo=444 is adjacent to Casing Design
    # x_hi=444, so Thermocouple correctly cuts Casing Design's y_bot).
    for row in rows:
        if len(row) != 1:
            continue
        a = row[0]
        if a.x0 <= 400:
            continue
        left_boundary = max(
            (b.x_hi for b in anchors if b.x_hi < a.x0),
            default=RIGHT_COL_X_LO
        )
        a.x_lo = left_boundary

    # Assign y bounds: from header top to next overlapping or adjacent header's top
    all_sorted = sorted(anchors, key=lambda x: (x.top, x.x0))
    for a in all_sorted:
        a.y_top = a.top

        # Use a small threshold (5pt) so that sections whose x-ranges are
        # "nearly adjacent" — e.g. Casing Design [~280,449] and Logging
        # Information [0,~290] which only share ~10pt — still properly
        # clip each other's y_bot.  The old 30pt threshold caused Casing
        # Design's y_bot to fall through to the footer, pulling Logging
        # Information notes/run-descriptions into the Casing Design crop.
        MIN_OVERLAP_PT = 5
        y_bot = page_height
        a_width = (PAGE_X_HI if a.x_hi >= 9999 else a.x_hi) - a.x_lo
        for b in all_sorted:
            if b.top <= a.top + SAME_LINE_TOL:
                continue
            overlap = min(b.x_hi, a.x_hi) - max(b.x_lo, a.x_lo)
            if overlap >= min(MIN_OVERLAP_PT, a_width * 0.3):
                y_bot = min(y_bot, b.top)
                break
        a.y_bot = y_bot

    # Widen explicitly full-width sections to x_lo=0.
    # These sections have headers in the right column but table content
    # starting near the left margin (x~50).
    for row in rows:
        if len(row) != 1:
            continue
        a = row[0]
        if a.name in FULL_WIDTH_SECTIONS:
            a.x_lo = 0

    return {a.name: a for a in anchors}


# ── Raw text extraction ───────────────────────────────────────────────────────

def extract_section_text(page, anchor):
    """Crop page to section bounds and return plain text."""
    # Subtract a small epsilon from y_bot so pdfplumber's inclusive crop does
    # not capture the header line of the next section (which sits at exactly y_bot).
    region = page.crop((anchor.x_lo, anchor.y_top, anchor.x_hi, anchor.y_bot - 0.5))
    return (region.extract_text() or "").strip()


# ── Geological formation structured parser ────────────────────────────────────

def detect_geo_column_boundaries(words):
    lines = build_line_index(words)
    header_row = None
    for _, line_words in sorted(lines.items()):
        texts = [w["text"] for w in line_words]
        has_geo  = any(w["text"] == "Geological" and w["x0"] < 320 for w in line_words)
        has_masl = "masl" in texts
        if has_geo and has_masl:
            header_row = line_words
            break
    if header_row is None:
        raise ValueError("Could not locate geological formation column header row")

    anchor_x = {}
    for col_key, seq in GEO_COL_SEQUENCES:
        for i, w in enumerate(header_row):
            if w["text"] == seq[0] and sequence_starts_at(header_row, seq, i):
                anchor_x[col_key] = w["x0"]
                break

    missing = [c for c, _ in GEO_COL_SEQUENCES if c not in anchor_x]
    if missing:
        raise ValueError(f"Missing geo column headers: {missing}")

    ordered = [c for c, _ in GEO_COL_SEQUENCES]
    n = len(ordered)
    boundaries = []
    for i, col in enumerate(ordered):
        if i == 0:
            x_lo = anchor_x[col] - 2  # small buffer: region.extract_words() can return
                                       # coords slightly less than all_words coords for
                                       # words at the exact left column edge
            x_hi = anchor_x[ordered[1]] - FORMATION_RIGHT_MARGIN
        elif i == n - 1:
            x_lo = (anchor_x[ordered[i-1]] + anchor_x[col]) / 2
            x_hi = 9999
        else:
            x_lo = (anchor_x[ordered[i-1]] + anchor_x[col]) / 2
            x_hi = (anchor_x[col] + anchor_x[ordered[i+1]]) / 2
        boundaries.append((col, x_lo, x_hi))
    return boundaries


def assign_column(x0, boundaries):
    for name, lo, hi in boundaries:
        if lo <= x0 < hi:
            return name
    return None


def row_to_formation(row_words, boundaries):
    buckets = {name: [] for name, *_ in boundaries}
    for w in sorted(row_words, key=lambda x: x["x0"]):
        col = assign_column(w["x0"], boundaries)
        if col:
            buckets[col].append(w["text"])

    def join(key):
        return " ".join(buckets[key]).strip() or None

    return {
        "formation":                   join("formation"),
        "masl_tvd":                    parse_float_or_none(join("masl_tvd")),
        "mkb_tvd":                     parse_float_or_none(join("mkb_tvd")),
        "pressure_kpa":                parse_float_or_none(join("pressure_kpa")),
        "emw_kg_m3":                   parse_float_or_none(join("emw_kg_m3")),
        "potential_drilling_problems": join("potential_drilling_problems"),
    }


SKIP_PREFIXES = {"geological formation", "note:"}


def is_formation_row(record):
    name = (record["formation"] or "").lower().strip()
    if not name or any(name.startswith(s) for s in SKIP_PREFIXES):
        return False
    return not (record["masl_tvd"] is None and record["mkb_tvd"] is None)


def parse_geo_formations(page, anchor, all_words):
    boundaries = detect_geo_column_boundaries(all_words)
    region = page.crop((anchor.x_lo, anchor.y_top, anchor.x_hi, anchor.y_bot - 0.5))
    region_words = region.extract_words()
    rows = group_words_into_rows(region_words)
    records = [row_to_formation(r, boundaries) for r in rows]
    return [r for r in records if is_formation_row(r)]


def parse_surface_location(page, anchor):
    """
    Parse Surface Location Information into two structured sub-sections:

      elevation:
        ground_level_masl  - Ground Level (masl)
        kb_ground_level_m  - KB - Ground Level (m)
        kb_elevation_mss   - KB Elevation (mSS)

      coordinates:
        system    - e.g. "NAD83 UTM"
        northing  - Northing value
        easting   - Easting value
    """
    region = page.crop((anchor.x_lo, anchor.y_top, anchor.x_hi, anchor.y_bot - 0.5))
    rwords = region.extract_words()
    lines  = build_line_index(rwords)
    sorted_lines = sorted(lines.items())

    # Skip the title row
    data_lines = [(top, lw) for top, lw in sorted_lines
                  if not any(w["text"] in ("Surface", "Location", "Information") for w in lw)]

    # Find the x split between elevation (left) and coordinate (right) columns.
    # The right column starts at "NAD83" or "Northing" or "Easting".
    split_x = None
    for _, lw in data_lines:
        for w in lw:
            if w["text"] in ("NAD83", "Northing:", "Easting:"):
                split_x = w["x0"]
                break
        if split_x:
            break

    if split_x is None:
        split_x = (anchor.x_lo + anchor.x_hi) / 2  # fallback: midpoint

    # Known row label tokens for the elevation column — ALL must be present
    ELEV_LABELS = {
        "ground_level_masl": {"Ground", "Level", "(masl):"},
        "kb_ground_level_m": {"KB", "Ground", "Level", "(m):"},
        "kb_elevation_mss":  {"KB", "Elevation", "(mSS):"},
    }

    ALL_LABEL_TOKENS = {t for tokens in ELEV_LABELS.values() for t in tokens}
    # Noise words that appear mid-row but aren't the numeric value
    NOISE = {"To", "be", "updated", "once", "rig", "onsite", "-", "NAD83", "UTM", "Coordinates"}

    elevation = {}
    for _, lw in data_lines:
        left_words = [w for w in lw if w["x0"] < split_x]
        if not left_words:
            continue
        row_tokens = {w["text"] for w in left_words}
        matched_field = None
        for field, label_tokens in ELEV_LABELS.items():
            if label_tokens <= row_tokens:  # subset: ALL label tokens must be present
                matched_field = field
                break
        if matched_field is None or matched_field in elevation:
            continue
        # Value = first word that looks numeric (contains a digit), excluding labels/noise
        value_words = [w for w in left_words
                       if w["text"] not in ALL_LABEL_TOKENS
                       and w["text"] not in NOISE
                       and any(c.isdigit() for c in w["text"])]
        elevation[matched_field] = value_words[0]["text"] if value_words else ""

    # ── Coordinate fields ─────────────────────────────────────────────────────
    coord_system = ""
    northing = ""
    easting  = ""
    for _, lw in data_lines:
        right_words = [w for w in lw if w["x0"] >= split_x]
        if not right_words:
            continue
        texts = [w["text"] for w in right_words]
        # System line: contains "NAD83"
        if "NAD83" in texts:
            coord_system = " ".join(t for t in texts
                                    if t not in ("Northing:", "Easting:")).strip()
        if "Northing:" in texts:
            idx = texts.index("Northing:")
            northing = " ".join(texts[idx+1:]).strip()
        if "Easting:" in texts:
            idx = texts.index("Easting:")
            easting = " ".join(texts[idx+1:]).strip()

    return {
        "elevation": {
            "ground_level_masl": elevation.get("ground_level_masl", ""),
            "kb_ground_level_m": elevation.get("kb_ground_level_m", ""),
            "kb_elevation_mss":  elevation.get("kb_elevation_mss", ""),
        },
        "coordinates": {
            "system":   coord_system,
            "northing": northing,
            "easting":  easting,
        },
    }


def parse_casing_design(page, anchor):
    """
    Parse Casing Design section into column-oriented structure.

    The section has a row-label column on the left and 2–3 data columns:
      Surface, (Intermediate — if present), Main

    Extracts three specific rows by position:
      row 0 → hole_size  (first row: size of hole)
      row 1 → depth      (second row: depth of hole)
      row 3 → casing_od  (fourth row: outer diameter)

    Returns a dict:
      {
        "columns": ["surface", "intermediate", "main"],   # or ["surface", "main"]
        "surface":      {"hole_size": "311", "depth": "200", "casing_od": "219"},
        "intermediate": {"hole_size": "222", "depth": "150", "casing_od": "168"},
        "main":         {"hole_size": "159", "depth": "500", "casing_od": "127"}
      }
    """
    region = page.crop((anchor.x_lo, anchor.y_top, anchor.x_hi, anchor.y_bot - 0.5))
    rwords = region.extract_words()
    lines  = build_line_index(rwords)
    sorted_lines = sorted(lines.items())

    # ── Find the column header row (contains "Surface" and "Main") ────────────
    header_top = None
    col_centres = {}

    for top, lw in sorted_lines:
        texts = [w["text"] for w in lw]
        if "Surface" in texts and "Main" in texts:
            header_top = top
            for w in lw:
                t = w["text"]
                cx = (w["x0"] + w["x1"]) / 2
                if t == "Surface":                    col_centres["surface"] = cx
                if t in ("Int.", "Intermediate"):     col_centres["intermediate"] = cx
                if t == "Main":                       col_centres["main"] = cx
            break

    if header_top is None or len(col_centres) < 2:
        return None

    # ── Determine row-label x boundary from the first data row ───────────────
    # Find the largest gap between consecutive word x0 positions in the first
    # data row — everything left of that gap is the row label, right is data.
    row_label_hi = None
    for top, lw in sorted_lines:
        if top <= header_top + 1:
            continue
        if len(lw) >= 2:
            xs = sorted(w["x0"] for w in lw)
            gaps = [(xs[i+1] - xs[i], xs[i], xs[i+1]) for i in range(len(xs)-1)]
            if gaps:
                max_gap, gap_lo, gap_hi = max(gaps)
                row_label_hi = (gap_lo + gap_hi) / 2
            break

    if row_label_hi is None:
        row_label_hi = min(col_centres.values()) - 10

    # ── Also fix the crop x_lo to skip logging bleedover ─────────────────────
    # Bleedover words from Logging Information appear at x < row_label_hi
    # but with x0 close to anchor.x_lo (i.e. they're left-edge fragments).
    # We already handle this by only reading words with x0 >= the leftmost
    # row label x — which we infer from the first data row above.
    # Re-crop the region with the corrected x_lo to drop bleedover words.
    first_label_x = None
    for top, lw in sorted_lines:
        if top <= header_top + 1:
            continue
        if lw:
            first_label_x = min(w["x0"] for w in lw)
            break

    if first_label_x and first_label_x > anchor.x_lo + 5:
        region = page.crop((first_label_x - 2, anchor.y_top, anchor.x_hi, anchor.y_bot - 0.5))
        rwords = region.extract_words()
        lines  = build_line_index(rwords)
        sorted_lines = sorted(lines.items())

    # ── Ordered column list for nearest-centre assignment ─────────────────────
    COLS_ORDER = ["surface", "intermediate", "main"]
    col_list = [(c, col_centres[c]) for c in COLS_ORDER if c in col_centres]

    def nearest_col(x0):
        return min(col_list, key=lambda p: abs(p[1] - x0))[0]

    def bucket_text(buckets, col):
        return " ".join(buckets.get(col, [])).strip()

    # ── Parse data rows ───────────────────────────────────────────────────────
    # Map row index → field key (0=hole_size, 1=hole_depth, 3=outer_diameter)
    FIELD_MAP = {0: "hole_size", 1: "depth", 3: "casing_od"}

    col_names = [c for c, _ in col_list]
    col_data  = {c: {} for c in col_names}

    row_idx = 0
    for top, lw in sorted_lines:
        if top <= header_top + 1:
            continue
        label_words = [w for w in lw if w["x0"] < row_label_hi]
        data_words  = [w for w in lw if w["x0"] >= row_label_hi]

        field = " ".join(w["text"] for w in sorted(label_words, key=lambda w: w["x0"])).strip()
        if not field:
            continue

        if row_idx in FIELD_MAP:
            key = FIELD_MAP[row_idx]
            buckets = {c: [] for c in col_names}
            for w in data_words:
                buckets[nearest_col(w["x0"])].append(w["text"])
            for c in col_names:
                col_data[c][key] = bucket_text(buckets, c)

        row_idx += 1

    result = {"columns": col_names}
    for c in col_names:
        result[c] = col_data[c]
    return result


def parse_drilling_fluids(page, anchor):
    """
    Parse Drilling Fluids section into structured rows, one per hole section.

    Each row dict has keys:
      hole_section, hole_size_mm, interval_mkb, system_type,
      density_kg_m3, viscosity_s_l, fluid_loss_ml, ph, comments

    Uses nearest-centre column assignment so sub-pixel misalignments between
    header and data words never cause words to fall into the wrong bucket.
    """
    region = page.crop((anchor.x_lo, anchor.y_top, anchor.x_hi, anchor.y_bot - 0.5))
    rwords = region.extract_words()
    lines  = build_line_index(rwords)
    sorted_lines = sorted(lines.items())

    # ── Find the header row that contains "(mm)" and "(mKB)" ─────────────────
    header2_top = None
    for top, lw in sorted_lines:
        texts = [w["text"] for w in lw]
        if "(mm)" in texts and "(mKB)" in texts:
            header2_top = top
            break

    if header2_top is None:
        return None

    # Map of column name → representative x centre (from header words)
    HEADER_TOKENS = {
        "(mm)":       "hole_size_mm",
        "(mKB)":      "interval_mkb",
        "Type":       "system_type",
        "(kg/m3)":    "density",
        "(s/L)":      "viscosity",
        "(mL/30min)": "fluid_loss",
        "pH":         "ph",
        "Comments":   "comments",
    }
    col_centres = {}
    for top, lw in sorted_lines:
        if abs(top - header2_top) > 10:
            continue
        for w in lw:
            if w["text"] in HEADER_TOKENS:
                col_name = HEADER_TOKENS[w["text"]]
                # Use centre of the header word as the column centre
                col_centres[col_name] = (w["x0"] + w["x1"]) / 2

    # hole_section has no neat header token — anchor it at x=0 conceptually;
    # its "centre" for nearest-match is halfway between 0 and hole_size_mm x_lo.
    if "hole_size_mm" in col_centres:
        col_centres["hole_section"] = col_centres["hole_size_mm"] / 2
    else:
        col_centres["hole_section"] = 0

    if len(col_centres) < 5:
        return None

    # Ordered list of (col_name, centre_x) for nearest-centre lookup
    COLS_ORDER = ["hole_section", "hole_size_mm", "interval_mkb", "system_type",
                  "density", "viscosity", "fluid_loss", "ph", "comments"]
    col_list = [(c, col_centres[c]) for c in COLS_ORDER if c in col_centres]

    def nearest_col(x0):
        return min(col_list, key=lambda p: abs(p[1] - x0))[0]

    # ── Note/footer row detection ─────────────────────────────────────────────
    # Full-width note lines (e.g. "Do NOT use LCM...") start at the far left
    # (x < hole_size_mm centre) and contain no numeric hole-size token.
    # We stop collecting data rows once we hit the first such line after
    # at least one valid data row has been found.
    NOTE_STARTERS = {"do", "refer", "note", "volumes", "see", "alap"}

    def is_note_line(lw):
        if not lw:
            return False
        first_text = lw[0]["text"].lower().rstrip(".")
        return first_text in NOTE_STARTERS

    # ── Parse data rows ───────────────────────────────────────────────────────
    records = []
    current = None
    found_data = False

    for top, lw in sorted_lines:
        if top <= header2_top + 1:
            continue  # skip title + header rows

        # Stop at note lines once we have at least one valid row
        if found_data and is_note_line(lw):
            break

        # Assign every word on this line to its nearest column
        buckets = {c: [] for c in col_centres}
        for w in lw:
            buckets[nearest_col(w["x0"])].append(w["text"])

        def bucket_text(col):
            return " ".join(buckets.get(col, [])).strip()

        hole_sec  = bucket_text("hole_section")
        hole_size = bucket_text("hole_size_mm")

        if hole_sec and hole_size:
            # New data row
            found_data = True
            current = {
                "hole_section":  hole_sec,
                "hole_size_mm":  hole_size,
                "interval_mkb":  bucket_text("interval_mkb"),
                "system_type":   bucket_text("system_type"),
                "density_kg_m3": bucket_text("density"),
                "viscosity_s_l": bucket_text("viscosity"),
                "fluid_loss_ml": bucket_text("fluid_loss"),
                "ph":            bucket_text("ph"),
                "comments":      bucket_text("comments"),
            }
            records.append(current)
        elif current is not None:
            # Continuation line — append any comment overflow
            extra = bucket_text("comments")
            if extra:
                current["comments"] = (current["comments"] + " " + extra).strip()

    # Organise by hole section key
    section_keys = []
    result = {}
    for rec in records:
        key = rec["hole_section"].lower().replace(" ", "_")
        section_keys.append(key)
        result[key] = {k: v for k, v in rec.items() if k != "hole_section"}
    result["sections"] = section_keys
    return result


def parse_logging_information(page, anchor):
    """
    Parse Logging Information section into two structured columns:
      tool_types  - left column: tool name + whether it's run (e.g. "Gamma Ray: YES")
      runs        - middle column: run descriptions (e.g. "Run #1:Gamma Ray/...")

    The right-hand notes column is left in raw_text only.

    Returns dict with tool_types and runs as lists of strings,
    or None if the header row cannot be located.
    """
    region = page.crop((anchor.x_lo, anchor.y_top, anchor.x_hi, anchor.y_bot - 0.5))
    rwords = region.extract_words()
    lines  = build_line_index(rwords)

    # ── Find the header row: contains "Tool" and "Run" ───────────────────────
    header_top   = None
    header_row   = None
    header_x_run = None

    sorted_lines = sorted(lines.items())
    for top, lw in sorted_lines:
        texts = [w["text"] for w in lw]
        if "Tool" in texts and "Run" in texts:
            header_top   = top
            header_row   = lw
            run_word     = next(w for w in lw if w["text"] == "Run")
            header_x_run = run_word["x0"]
            break

    if header_top is None:
        return None

    # ── Column x boundaries ───────────────────────────────────────────────────
    # col1: [0,       col1_hi]  – tool types
    # col2: [col1_hi, col2_hi]  – runs in well
    # col3: [col2_hi, ∞      ]  – notes (returned as joined string)
    col1_end = max(w["x1"] for w in header_row if w["x0"] < header_x_run - 5)
    col1_hi  = (col1_end + header_x_run) / 2

    # col2_hi: right edge of "Well" in the "Run in Well" header phrase.
    # Fallback to a fixed offset if "Well" isn't found.
    well_word = next((w for w in header_row if w["text"] == "Well"), None)
    col2_hi   = (well_word["x1"] + 5) if well_word else (col1_hi + 60)

    # ── Parse data rows ───────────────────────────────────────────────────────
    HEADER_TOL = 2  # pt
    col1_rows, col2_rows, col3_lines = [], [], []

    for top, lw in sorted_lines:
        if top < header_top - HEADER_TOL:
            continue
        on_header = abs(top - header_top) <= HEADER_TOL
        if on_header:
            continue  # skip the header row itself
        c1 = " ".join(w["text"] for w in lw if w["x0"] <  col1_hi).strip()
        c2 = " ".join(w["text"] for w in lw if col1_hi <= w["x0"] < col2_hi).strip()
        c3 = " ".join(w["text"] for w in lw if w["x0"] >= col2_hi).strip()
        if c1: col1_rows.append(c1)
        if c2: col2_rows.append(c2)
        if c3: col3_lines.append(c3)

    return {
        "tool_types": col1_rows,
        "runs":       col2_rows,
        "notes":      "\n".join(col3_lines),
    }


# ── Well metadata ─────────────────────────────────────────────────────────────

# UWI format: 100(1AA)/01-23-092-05W4/00  or  1AA/09-30-095-06W4/0
_UWI_RE = re.compile(r'(?:100)?\(?1[A-Z]{2}\)?/\d{2}-\d{2}-\d{3}-\d{2}[A-Z]\d/\d+')

# Location code on the title line: digits-digits-digits-digits+letter (e.g. 9-30-95-6 or 1-23-92-5W4)
_LOC_RE = re.compile(r'\d+-\d+-\d+-\d+[A-Z]\d[A-Z]?\d*')


def extract_well_metadata(words):
    """
    Extract metadata from the page header area (top ~55pt).

    Fields returned:
      well_id     - the short ID from General Information box (e.g. "OB301", "LS4")
      licence     - the AER licence number from General Information box
      well_name   - full title-line name (e.g. "SUNCOR LS4 1-23-92-5W4")
      uwi         - unique well identifier (e.g. "100(1AA)/01-23-092-05W4/00")
    """
    meta = {"well_id": None, "licence": None, "well_name": None, "uwi": None}

    # ── well_id and licence from General Information box ──────────────────────
    for i, w in enumerate(words):
        if w["text"] == "ID:" and i + 1 < len(words):
            meta["well_id"] = words[i + 1]["text"]
        if w["text"] == "#:" and i + 1 < len(words):
            meta["licence"] = words[i + 1]["text"]

    # ── well_name and UWI from the centred title at the top of the page ───────
    # The title spans x=[230, 380] (approx centre of page) and top < 90pt.
    # Line 1 starts with "SUNCOR": collect all words on that line.
    # Line 2 contains the UWI token.
    lines = {}
    for w in words:
        if w["top"] < 90 and 200 < w["x0"] < 380:
            key = round(w["top"], 0)
            lines.setdefault(key, []).append(w)

    for top_key, line_words in sorted(lines.items()):
        sorted_lw = sorted(line_words, key=lambda x: x["x0"])
        texts = [w["text"] for w in sorted_lw]
        line_str = " ".join(texts)

        if texts and texts[0] == "SUNCOR":
            meta["well_name"] = line_str

        # UWI: look for our regex in the joined line text
        m = _UWI_RE.search(line_str)
        if m:
            meta["uwi"] = m.group(0)

    return meta


# ── Page extraction ───────────────────────────────────────────────────────────

def detect_footer_top(words, page_height):
    """
    Find the top y-coordinate of the page-wide footer line containing
    'Prepared By:', 'Prognosis Date:', and 'Printed Date:'.
    Returns that y value as the effective page bottom (so sections don't
    capture the footer), or page_height if no footer is found.
    """
    FOOTER_KEYWORDS = {"Prepared", "Prognosis", "Printed"}
    # Only look in the bottom 20% of the page
    threshold = page_height * 0.8
    for w in words:
        if w["top"] > threshold and w["text"] in FOOTER_KEYWORDS:
            return w["top"]
    return page_height


def extract_page(page, requested_sections):
    all_words   = page.extract_words()
    footer_top  = detect_footer_top(all_words, page.height)
    anchors     = detect_section_anchors(all_words)
    bounds      = compute_bounds(anchors, footer_top, words=all_words)
    meta        = extract_well_metadata(all_words)

    sections = {}
    for name in requested_sections:
        anchor = bounds.get(name)
        if anchor is None:
            sections[name] = None
            continue

        if name == "Geological Formation Information":
            sections[name] = {
                "raw_text":   extract_section_text(page, anchor),
                "rows": parse_geo_formations(page, anchor, all_words),
            }
        elif name == "Logging Information":
            sections[name] = {
                "raw_text": extract_section_text(page, anchor),
                "columns":  parse_logging_information(page, anchor),
            }
        elif name == "Drilling Fluids":
            sections[name] = {
                "raw_text": extract_section_text(page, anchor),
                "fluids": parse_drilling_fluids(page, anchor),
            }
        elif name == "Casing Design":
            sections[name] = {
                "raw_text": extract_section_text(page, anchor),
                "casing":   parse_casing_design(page, anchor),
            }
        elif name == "Surface Location Information":
            sections[name] = {
                "raw_text": extract_section_text(page, anchor),
                "location": parse_surface_location(page, anchor),
            }
        else:
            sections[name] = {"raw_text": extract_section_text(page, anchor)}

    # ── Enrich casing design with system_type from drilling fluids ───────────
    casing_section = sections.get("Casing Design")
    fluids_section = sections.get("Drilling Fluids")
    if casing_section and fluids_section:
        casing_data = casing_section.get("casing")
        fluids_data = fluids_section.get("fluids")
        if casing_data and fluids_data:
            fluid_keys = fluids_data.get("sections", [])
            for col in casing_data.get("columns", []):
                system_type = ""
                for fluid_key in fluid_keys:
                    if fluid_key.startswith(col) or col in fluid_key:
                        system_type = fluids_data[fluid_key].get("system_type", "")
                        break
                casing_data[col]["system_type"] = system_type

    return {
        "page":      page.page_number,
        "well_name": meta["well_name"],
        "uwi":       meta["uwi"],
        "well_id":   meta["well_id"],
        "licence":   meta["licence"],
        "sections":  sections,
    }


def is_valid_well_stick(page_result):
    """
    Return True if the page looks like a genuine well stick diagram.
    A page where all metadata and all sections are None is almost certainly
    an unrelated document (cover page, index, non-well PDF, etc.).
    """
    meta_fields = ("well_name", "uwi", "well_id", "licence")
    if any(page_result.get(f) is not None for f in meta_fields):
        return True
    if any(v is not None for v in page_result.get("sections", {}).values()):
        return True
    return False


def extract_pdf(pdf_path, requested_sections):
    results = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            try:
                page_result = extract_page(page, requested_sections)
                if not is_valid_well_stick(page_result):
                    print(
                        f"[WARN] Page {page.page_number}: no well stick data detected — "
                        f"this may not be a valid well stick diagram.",
                        file=sys.stderr,
                    )
                    page_result["valid"] = False
                else:
                    page_result["valid"] = True
                results.append(page_result)
            except Exception as e:
                print(f"[WARN] Page {page.page_number}: {e}", file=sys.stderr)
    return results


# ── CLI ───────────────────────────────────────────────────────────────────────

ALL_SECTIONS = [name for name, _ in SECTION_REGISTRY]

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: python3 {sys.argv[0]} <pdf_path> [section1] [section2] ...",
              file=sys.stderr)
        print(f"Available sections: {ALL_SECTIONS}", file=sys.stderr)
        sys.exit(1)

    pdf_path = sys.argv[1]
    requested = sys.argv[2:] if len(sys.argv) > 2 else ALL_SECTIONS

    unknown = [s for s in requested if s not in ALL_SECTIONS]
    if unknown:
        print(f"[ERROR] Unknown section(s): {unknown}", file=sys.stderr)
        sys.exit(1)

    data = extract_pdf(pdf_path, requested)
    print(json.dumps(data, indent=2))