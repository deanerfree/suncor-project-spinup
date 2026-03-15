# Suncor Project Spinup

A full-stack web application that automates the extraction and reporting workflow for oil well drilling operations. Engineers upload a well stick diagram PDF, review the extracted data, and download pre-populated Excel reports — eliminating hours of manual data entry per well.

Built with **Elixir/Phoenix LiveView** on the backend and **Python (pdfplumber + openpyxl)** for PDF parsing and Excel generation.

---

## The Problem It Solves

When a new well is spun up, drilling engineers receive a well stick diagram PDF containing geological, casing, drilling fluid, and logging data. Historically, this data had to be manually transcribed into several Excel report templates — a slow, error-prone process.

This application automates that pipeline:

1. **Upload** a well stick diagram PDF
2. **Review** the extracted data and fill in rig details
3. **Download** fully populated Excel reports

---

## Tech Stack

| Layer | Technology |
|---|---|
| Web framework | [Phoenix](https://www.phoenixframework.org/) 1.8 with LiveView 1.1 |
| Language | Elixir (backend) + Python 3 (data processing) |
| PDF extraction | [pdfplumber](https://github.com/jsvine/pdfplumber) |
| Excel generation | [openpyxl](https://openpyxl.readthedocs.io/) |
| Styling | Tailwind CSS + daisyUI |
| Icons | Heroicons v2 |
| HTTP server | Bandit |

No database — all data flows through in-memory Elixir maps and the user's browser `localStorage`, keeping the application stateless and simple to deploy.

---

## Architecture Overview

```
User Browser
    │
    │  (1) Upload PDF (LiveView file upload)
    ▼
Phoenix LiveView (HomeLive)
    │
    │  (2) Spawn subprocess
    ▼
Python: extract_pdf_data.py   ←── pdfplumber reads PDF
    │
    │  (3) JSON → Elixir map → pushEvent to browser localStorage
    ▼
Phoenix LiveView (ReviewLive)
    │
    │  (4) User reviews/edits, submits form
    ▼
ProjectSpinup.GenServer
    │
    │  (5) Spawn subprocess with JSON payload
    ▼
Python: build_excel.py   ←── openpyxl writes Excel templates
    │
    │  (6) File paths returned, Phoenix.Token signed, navigate to download
    ▼
Phoenix LiveView (DownloadLive) + DownloadController
```

The Elixir `GenServer` is the orchestration layer between the web UI and the two Python scripts.

---

## Key Modules

### Elixir

| Module | Responsibility |
|---|---|
| `ProjectSpinup.GenServer` | OTP GenServer; coordinates PDF parsing and Excel generation |
| `ProjectSpinup.WellStickParser` | Spawns the Python extraction script, parses and validates the JSON response |
| `ProjectSpinupWeb.HomeLive` | Drag-and-drop PDF upload, file validation, localStorage handoff |
| `ProjectSpinupWeb.ReviewLive` | Review/edit extracted data, submit for report generation |
| `ProjectSpinupWeb.DownloadLive` | Token-verified download page with file size display |
| `ProjectSpinupWeb.DownloadController` | Serves files with `Content-Disposition: attachment`, validates Phoenix tokens |
| `ProjectSpinupWeb.Layouts` | Shared layouts including the 3-step workflow progress header |

### Python

| Script | Responsibility |
|---|---|
| `priv/python/extract_pdf_data.py` | Coordinate-based section detection in PDFs; outputs structured JSON for 13 named well sections |
| `priv/python/build_excel.py` | Populates Excel templates (EOW Report, AM Report, Mud Resistivity, Sample Descriptions) |

---

## Data Flow in Detail

### PDF Extraction (`extract_pdf_data.py`)

The script uses pdfplumber's coordinate system to locate and bound each of the 13 well stick sections (e.g. *Geological Formation Information*, *Casing Design*, *Drilling Fluids*). Sections are detected by multi-word header sequences, and content is extracted within bounding boxes.

Structured sections return typed data:
- **Geological Formations** → rows with formation name, MASL TVD, mKB TVD, pressure (kPa), EMW (kg/m³), drilling problems
- **Drilling Fluids** → rows with hole section, interval, fluid system, density, viscosity, fluid loss, pH
- **Casing Design** → columns per casing string (surface, intermediate, production)
- **Location** → elevation and coordinate fields

Unstructured sections return raw text strings.

### Excel Generation (`build_excel.py`)

Receives a JSON payload with well metadata, rig details, and all parsed sections. Uses openpyxl to:

- Open each `.xlsx` template from `priv/python/excel_templates/`
- Write structured data to the correct cells and rows
- Handle merged cell ranges when inserting or deleting rows
- Return a JSON array of output file paths

### Secure File Downloads

Generated files are served through `DownloadController`, which verifies a `Phoenix.Token` signed at report generation time. Tokens expire after 5 minutes, preventing unauthorized access to temp files.

---

## Running Locally

**Prerequisites:** Elixir 1.15+, Python 3 with `pdfplumber` and `openpyxl`

```bash
# Install Python dependencies
pip install pdfplumber openpyxl

# Install Elixir dependencies and set up assets
mix setup

# Start the development server
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

---

## Deploying to Fly.io

A `fly.toml` is included. Before deploying:

```bash
# Create the app
fly apps create project-spinup

# Set required secrets
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set PHX_HOST=project-spinup.fly.dev

# Deploy
fly deploy
```

---

## Project Structure

```
lib/
├── project_spinup/
│   ├── application.ex        # OTP supervisor
│   ├── gen_server.ex         # Orchestration GenServer
│   ├── well_stick_parser.ex  # PDF parsing coordinator
│   └── utils.ex              # Shared helpers
└── project_spinup_web/
    ├── live/
    │   ├── home_live.ex      # Upload page
    │   ├── review_live.ex    # Review & edit page
    │   └── download_live.ex  # Download page
    ├── controllers/
    │   └── download_controller.ex
    ├── components/
    │   ├── core_components.ex
    │   └── layouts.ex
    └── router.ex

priv/python/
├── extract_pdf_data.py       # PDF → JSON
├── build_excel.py            # JSON → Excel
└── excel_templates/          # .xlsx source templates
    ├── TEMPLATE_EOW Report.xlsx
    ├── TEMPLATE2_AM Report.xlsx
    ├── TEMPLATE_Mud Resistivity.xlsx
    └── TEMPLATE_Sample Descriptions.xlsx
```
