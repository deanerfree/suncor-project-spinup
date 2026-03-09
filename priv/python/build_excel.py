#!/usr/bin/env python3
"""
Script to convert the stick diagram PDF into an Excel file with the same data.
"""
import openpyxl
import json
import sys

templates = [
    'excel/TEMPLATE_EOW Report.xlsx',
    'excel/TEMPLATE_AM Report.xlsx',
    'excel/TEMPLATE_Mud Resistivity.xlsx',
    'excel/TEMPLATE_Sample Descriptions.xlsx',
]

def populate_eow_report(data):
    wb = openpyxl.load_workbook('excel/TEMPLATE_EOW Report.xlsx')
    ws = wb.active

    ws['A1'] = data['well_name']
    ws['A2'] = data['uwi']
    ws['A3'] = data['licence']

    wb.save(data["well_name"] + "_EOW Report.xlsx")
    return data['well_name'] + "_EOW Report.xlsx"


def main():
    data = json.loads(sys.stdin.read())

    files = []
    files.append(populate_eow_report(data))

    print(json.dumps({"status": "ok", "files": files}))


if __name__ == "__main__":
    main()