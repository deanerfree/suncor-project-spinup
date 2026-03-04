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
    ("Geological Formation Information", ["Geological", "Formation", "Information"]),
    ("Surface Location Information",     ["Surface",    "Location",  "Information"]),
    ("General Information",              ["General",    "Information"]),
    ("Drilling Notes",                   ["Drilling",   "Notes"]),
    ("Casing Accessories",               ["Casing",     "Accessories"]),
    ("Drilling Fluids",                  ["Drilling",   "Fluids"]),
    ("Cementing",                        ["Cementing"]),
    # "Cutting" (space-separated) or "Cutting/Coring" (slash-joined, no spaces)
    ("Drill Cutting / Coring Information", ["Drill", "Cutting"]),
    ("Drill Cutting / Coring Information", ["Drill", "Cutting/Coring"]),
    ("Casing Design",                    ["Casing",     "Design"]),
    ("Piezometer Design",                ["Piezometer", "Design"]),
    ("Logging Information",              ["Logging",    "Information"]),
    ("Thermocouple Design",              ["Thermocouple", "Design"]),
]

# Sections we can parse into structured data (beyond raw text)
STRUCTURED_SECTIONS = {"Geological Formation Information", "Logging Information"}

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
        for name, seq in SECTION_REGISTRY:
            for i, w in enumerate(line_words):
                if w["text"] == seq[0] and sequence_starts_at(line_words, seq, i):
                    last_word = line_words[i + len(seq) - 1]
                    found.append(SectionAnchor(name, w["x0"], last_word["x1"], top_key))
                    break   # don't double-match on the same line

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

        MIN_OVERLAP_PT = 30
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
            x_lo = anchor_x[col]
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


def parse_logging_information(page, anchor):
    """
    Parse Logging Information section into three structured columns:
      tool_types  - left column: tool name + whether it's run (e.g. "Gamma Ray: YES")
      runs        - middle column: run descriptions (e.g. "Run #1:Gamma Ray/...")
      notes       - right column: free-text notes (no fixed header)

    Returns dict with tool_types, runs, notes as lists of strings,
    or None if the header row cannot be located.
    """
    region = page.crop((anchor.x_lo, anchor.y_top, anchor.x_hi, anchor.y_bot - 0.5))
    rwords = region.extract_words()
    lines  = build_line_index(rwords)

    # ── Find the header row: contains "Tool" and "Run" ───────────────────────
    header_top  = None
    header_row  = None
    header_x_run = None
    header_x_notes = None

    sorted_lines = sorted(lines.items())
    for top, lw in sorted_lines:
        texts = [w["text"] for w in lw]
        if "Tool" in texts and "Run" in texts:
            header_top = top
            header_row = lw
            run_word   = next(w for w in lw if w["text"] == "Run")
            header_x_run = run_word["x0"]
            # Third column: first word after "Well" in the header row, if any
            well_idx = next((i for i, w in enumerate(lw) if w["text"] == "Well"), None)
            if well_idx is not None and well_idx + 1 < len(lw):
                header_x_notes = lw[well_idx + 1]["x0"]
            break

    if header_top is None:
        return None

    # If third column header wasn't on the same line, check the adjacent line
    # (Firebag puts "Note 1:..." on a slightly different y than "Tool Type Run in Well")
    if header_x_notes is None:
        for top, lw in sorted_lines:
            if abs(top - header_top) < 5 and top != header_top:
                candidates = [w for w in lw if w["x0"] > header_x_run + 10]
                if candidates:
                    header_x_notes = min(w["x0"] for w in candidates)
                    break
        if header_x_notes is None:
            # Fallback: notes column starts 60pt after run column
            header_x_notes = header_x_run + 60

    # ── Column x boundaries ───────────────────────────────────────────────────
    # col1: [0,         col1_hi]   – tool types
    # col2: [col1_hi,   col2_hi]   – runs in well
    # col3: [col2_hi,   ∞      ]   – notes
    col1_end  = max(w["x1"] for w in header_row if w["x0"] < header_x_run - 5)
    col1_hi   = (col1_end + header_x_run) / 2
    # col2_hi: use the right edge of the last "Run in Well" header word + a small
    # buffer. Using the midpoint to the next header risks including the "Run" in
    # "Run #1:..." (which sits just below the midpoint) in the wrong column.
    run_words = [w for w in header_row if header_x_run <= w["x0"] < header_x_notes - 5]
    col2_end  = max((w["x1"] for w in run_words), default=header_x_notes)
    col2_hi   = col2_end + 10  # tight boundary just past the last "Run in Well" word

    # ── Parse data rows ───────────────────────────────────────────────────────
    # Collect words per column per row, then join into strings
    HEADER_TOL = 2  # pt: skip rows within this distance of the header
    col1_rows, col2_rows, col3_rows = [], [], []

    for top, lw in sorted_lines:
        # Skip the section title row and rows at/above header
        if top < header_top - HEADER_TOL:
            continue
        c1 = " ".join(w["text"] for w in lw if w["x0"] <  col1_hi).strip()
        c2 = " ".join(w["text"] for w in lw if col1_hi <= w["x0"] < col2_hi).strip()
        c3 = " ".join(w["text"] for w in lw if w["x0"] >= col2_hi).strip()
        # On the header row itself, col1/col2 contain the column titles — skip them.
        # But still capture notes (col3) which may start on the same y (e.g. Firebag
        # puts "Note 1:..." at the same y as "Tool Type Run in Well").
        on_header = abs(top - header_top) <= HEADER_TOL
        if on_header:
            c1, c2 = "", ""
        if c1: col1_rows.append(c1)
        if c2: col2_rows.append(c2)
        if c3: col3_rows.append(c3)

    return {
        "tool_types": col1_rows,
        "runs":       col2_rows,
        "notes":      col3_rows,
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
    # The title spans x=[230, 350] (approx centre of page) and top < 55pt.
    # Line 1 starts with "SUNCOR": collect all words on that line.
    # Line 2 contains the UWI token.
    lines = {}
    for w in words:
        if w["top"] < 55 and 200 < w["x0"] < 380:
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
                "formations": parse_geo_formations(page, anchor, all_words),
            }
        elif name == "Logging Information":
            sections[name] = {
                "raw_text": extract_section_text(page, anchor),
                "columns":  parse_logging_information(page, anchor),
            }
        else:
            sections[name] = {"raw_text": extract_section_text(page, anchor)}

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