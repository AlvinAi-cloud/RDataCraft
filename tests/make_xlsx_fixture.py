"""Create a minimal spreadsheet fixture with no third-party Python dependencies."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

folder = Path(__file__).resolve().parent / "fixtures"
folder.mkdir(exist_ok=True)
files = {
    "[Content_Types].xml": '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>''',
    "_rels/.rels": '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
    "xl/workbook.xml": '''<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Observations" sheetId="1" r:id="rId1"/></sheets></workbook>''',
    "xl/_rels/workbook.xml.rels": '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>''',
    "xl/worksheets/sheet1.xml": '''<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:B4"/><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Control</t></is></c><c r="B1" t="inlineStr"><is><t>Treatment</t></is></c></row><row r="2"><c r="A2"><v>1</v></c><c r="B2"><v>2</v></c></row><row r="3"><c r="A3"><v>3</v></c><c r="B3"><v>5</v></c></row><row r="4"><c r="A4"><v>6</v></c><c r="B4"><v>9</v></c></row></sheetData></worksheet>''',
}
with ZipFile(folder / "observations.xlsx", "w", ZIP_DEFLATED) as archive:
    for name, text in files.items():
        archive.writestr(name, '<?xml version="1.0" encoding="UTF-8"?>' + text)
