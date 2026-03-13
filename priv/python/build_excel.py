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

def populate_am_report(data, output_dir):
    wb = openpyxl.load_workbook(os.path.join(TEMPLATE_DIR, 'TEMPLATE_AM Report.xlsx'))
    ws = wb.active

    mcmurray_top = 0
    total_depth = 0

    # Build general information
    ws['C8'] = data.get('rig_name', '')
    ws['C11'] = data['licence']
    ws['D2'] = data['well_name']
    ws['D3'] = data['uwi']
    ws['C13'] = data.get('spud_date', '')
    ws['I5'] = data.get('og', '')
    ws['L5'] = data.get('og_ph', '')
    ws['I6'] = data.get('geo_day', '')
    ws['L6'] = data.get('geo_day_ph', '')
    ws['I7'] = data.get('geo_night', '')
    ws['L7'] = data.get('geo_night_ph', '')
    ws['I8'] = data.get('wss_day', '')
    ws['I9'] = data.get('wss_night', '')
    ws['L9'] = data.get('rig_ph', '')

    # Build geological formation information
    for i, item in enumerate(data['sections']['Geological Formation Information']['rows'], start=1):
        if mcmurray_top == 0 and 'mcmurray' in item['formation'].lower():
            mcmurray_top = round(item['mkb_tvd'])
        if item['formation'].lower() == 'total depth':
            total_depth = item['mkb_tvd']
        
        ws[f'A{33 + i}'] = item['formation']
        ws[f'D{33 + i}'] = item['mkb_tvd']
        ws[f'E{33 + i}'] = item['mkb_tvd']
        ws[f'F{33 + i}'] = item['masl_tvd']

    # Build mud resistivity information
    resistivity_start = mcmurray_top - 20
    row = 34
    while resistivity_start <= total_depth:
        ws[f'L{row}'] = resistivity_start
        resistivity_start += 50
        row += 1

    # Resistivity report generation
    out_path = os.path.join(output_dir, data["well_name"] + "_AM Report.xlsx")
    wb.save(out_path)
    return out_path, mcmurray_top, total_depth


def populate_resistivity_report(data, output_dir, mcmurray_top, total_depth):
    wb = openpyxl.load_workbook(os.path.join(TEMPLATE_DIR, 'TEMPLATE_Mud Resistivity.xlsx'))
    ws = wb.active
    row = 6
    start = mcmurray_top - 20
    
    ws['A3'] = data['well_name']
    ws['A4'] = data['uwi']

    while start <= total_depth:
        ws[f'B{row}'] = start
        start += 50
        row += 1

    out_path = os.path.join(output_dir, data["well_name"] + "_Mud Resistivity.xlsx")
    wb.save(out_path)
    return out_path


def main():
    mcmurray_top = 0
    total_depth = 0
    data = json.loads(sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read())
    output_dir = data.get("output_dir", os.getcwd())

    files = []
    files.append(populate_eow_report(data, output_dir))
    am_report, mcmurray_top, total_depth = populate_am_report(data, output_dir)
    files.append(am_report)
    resistivity_report = populate_resistivity_report(data, output_dir, mcmurray_top, total_depth)
    files.append(resistivity_report)

    print(json.dumps({"status": "ok", "files": files}))


if __name__ == "__main__":
    main()