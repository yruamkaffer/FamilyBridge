"""Validation of both automation payloads and embedded binaries (offline)."""
from pathlib import Path
from zipfile import ZipFile
import json
import xml.etree.ElementTree as ET

base = Path(__file__).resolve().parents[1]
activity = json.loads((base / 'aps/revit2024/activity.template.json').read_text())
assert activity['engine'] == 'Autodesk.Revit+2024'
assert {v['localName'] for v in activity['parameters'].values()} == {
    'output.rfa', 'bodies.fbdat', 'steps.fbdat', 'metadata.json', 'colors.json', 'template.rft'
}
cs = (base / 'aps/revit2024/FamilyBridgeApp.cs').read_text()
for term in ('SATImportOptions', 'STEPImportOptions', 'ShapeImporterSourceFormat.SAT', 'DescribeGeometry(',
             'TessellatedShapeBuilderTarget.Mesh', 'CreateMeshFallback(', 'DirectShape.CreateElement',
             'FreeFormElement.Create', 'family.Delete(importId)',
             'bodies.fbdat', 'steps.fbdat', 'output.rfa',
             'box.Transform.OfPoint', 'WorldBounds(solid, out worldMin, out worldMax)',
             'volumeDifference >= 0.02', 'largestDimensionDifference >= 5.0',
             'largestAxisDifference >= 5.0'):
    assert term in cs
ET.parse(base / 'aps/revit2024/PackageContents.xml')
ET.parse(base / 'aps/fusion/FamilyBridgeStepToSat/PackageContents.xml')
fusion_source = (base / 'aps/fusion/FamilyBridgeStepToSat/Contents/main.ts').read_bytes()
assert b'moveToComponent(occurrence)' in fusion_source
assert b'copyToComponent(occurrence)' in fusion_source
assert fusion_source.index(b'copyToComponent(occurrence)') < fusion_source.index(b'moveToComponent(occurrence)')
assert b'Isolating body ${i + 1}/${sources.length}' in fusion_source
assert b'addNewComponent(adsk.core.Matrix3D.create())' in fusion_source
assert b'assertSameAssemblyBox(bodies[i], isolated, i + 1)' in fusion_source
assert b'createSATExportOptions(filename, isolatedBody.parentComponent)' in fusion_source
assert b'createSTEPExportOptions(stepName, isolatedBody.parentComponent)' in fusion_source
assert b'FBS1' not in fusion_source or b'70, 66, 83, 49' in fusion_source
assert b'Buffer' not in fusion_source and b'toString("ascii")' not in fusion_source
for resource, required in (
    ('FamilyBridgeAutomation2024.bundle.zip', 'FamilyBridgeAutomation.bundle/Contents/FamilyBridge.Automation.dll'),
    ('FamilyBridgeStepToSat.bundle.zip', 'FamilyBridgeStepToSat/Contents/main.ts'),
):
    with ZipFile(base / 'sketchup/family_bridge/resources' / resource) as bundle:
        assert required in bundle.namelist()
        if resource == 'FamilyBridgeAutomation2024.bundle.zip':
            worker = bundle.read(required)
            # The previous release accidentally shipped a 0.5.0 DLL that read
            # model.skp, although source and Activity already passed model.sat.
            for literal in ('worker 0.9.5 solid-first STEP retry RGB', 'bodies.fbdat', 'steps.fbdat', 'colors.json',
                            'FreeFormElements sólidos criados', 'individuais recebidos'):
                assert literal.encode('utf-16le') in worker, literal
            assert 'model.skp'.encode('utf-16le') not in worker
        else:
            assert bundle.read(required) == fusion_source
print('OK: engines, SAT/STEP, manifestos e AppBundles.')
