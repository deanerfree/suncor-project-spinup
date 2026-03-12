#!/usr/bin/env python3
"""
Script to convert the stick diagram PDF into an Excel file with the same data.
"""
import openpyxl
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_DIR = os.path.join(SCRIPT_DIR, "excel_templates")

templates = [
    os.path.join(TEMPLATE_DIR, 'TEMPLATE_EOW Report.xlsx'),
    os.path.join(TEMPLATE_DIR, 'TEMPLATE_AM Report.xlsx'),
    os.path.join(TEMPLATE_DIR, 'TEMPLATE_Mud Resistivity.xlsx'),
    os.path.join(TEMPLATE_DIR, 'TEMPLATE_Sample Descriptions.xlsx'),
]

def populate_eow_report(data, output_dir):
    wb = openpyxl.load_workbook(os.path.join(TEMPLATE_DIR, 'TEMPLATE_EOW Report.xlsx'))
    ws = wb.active

    ws['A3'] = data['well_name']
    ws['D3'] = data['uwi']
    ws['H3'] = data['licence']

    out_path = os.path.join(output_dir, data["well_name"] + "_EOW Report.xlsx")
    wb.save(out_path)
    return out_path


def main():
    data = json.loads(sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read())
    output_dir = data.get("output_dir", os.getcwd())

    files = []
    files.append(populate_eow_report(data, output_dir))

    print(json.dumps({"status": "ok", "files": files}))


if __name__ == "__main__":
    main()