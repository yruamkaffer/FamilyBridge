"""Validation of both automation payloads and embedded binaries (offline)."""
from pathlib import Path
from zipfile import ZipFile
import json
import xml.etree.ElementTree as ET

base = Path(__file__).resolve().parents[1]
activity = json.loads((base / 'aps/revit2024/activity.template.json').read_text())
assert activity['engine'] == 'Autodesk.Revit+2024'
assert {v['localName'] for v in activity['parameters'].values()} == {
    'output.rfa', 'model.sat', 'metadata.json', 'colors.json', 'template.rft'
}
cs = (base / 'aps/revit2024/FamilyBridgeApp.cs').read_text()
for term in ('SATImportOptions', 'FreeFormElement.Create', 'family.Delete(importId)', 'output.rfa'):
    assert term in cs
ET.parse(base / 'aps/revit2024/PackageContents.xml')
ET.parse(base / 'aps/fusion/FamilyBridgeStepToSat/PackageContents.xml')
for resource, required in (
    ('FamilyBridgeAutomation2024.bundle.zip', 'FamilyBridgeAutomation.bundle/Contents/FamilyBridge.Automation.dll'),
    ('FamilyBridgeStepToSat.bundle.zip', 'FamilyBridgeStepToSat/Contents/main.ts'),
):
    with ZipFile(base / 'sketchup/family_bridge/resources' / resource) as bundle:
        assert required in bundle.namelist()
print('OK: engines, SAT sólido, manifestos e AppBundles.')
