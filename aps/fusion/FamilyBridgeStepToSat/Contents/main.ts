import { adsk } from "@adsk/fas";
import { writeFileSync } from "fs";

// Fusion's internal lengths are centimetres; the manifest uses millimetres.
function record(body: adsk.fusion.BRepBody) {
  if (!body.isSolid) return null;
  const box = body.boundingBox;
  const dims = [box.maxPoint.x - box.minPoint.x,
                box.maxPoint.y - box.minPoint.y,
                box.maxPoint.z - box.minPoint.z].map(v => v * 10).sort((a, b) => a - b);
  const faceColors = new Set<string>();
  for (let i = 0; i < body.faces.count; i++) {
    const c = body.faces.item(i).appearance?.color;
    if (c) faceColors.add([c.red, c.green, c.blue].join(','));
  }
  // A single FreeFormElement can have one material. Never silently flatten a
  // body with different face colours into a misleading single colour.
  if (faceColors.size > 1) throw Error(`Body ${body.name} has multiple face colours; cannot preserve them as one Revit material`);
  const c = body.appearance?.color;
  const rgb = faceColors.size ? [...faceColors][0].split(',').map(Number) :
              c ? [c.red, c.green, c.blue] : null;
  return { name: body.name, dimensions_mm: dims,
           volume_mm3: body.physicalProperties.volume * 1000, rgb };
}

function run() {
  const app = adsk.core.Application.get();
  if (!app) throw Error("Fusion Application unavailable");

  const options = app.importManager.createSTEPImportOptions("inputFile.step");
  const document = app.importManager.importToNewDocument(options);
  if (!document) throw Error("STEP import failed");
  const design = document.products.itemByProductType("DesignProductType") as adsk.fusion.Design;
  if (!design) throw Error("STEP did not produce a Fusion design");
  const bodies: ReturnType<typeof record>[] = [];
  const root = design.rootComponent;
  for (let i = 0; i < root.bRepBodies.count; i++) {
    const r = record(root.bRepBodies.item(i)); if (r) bodies.push(r);
  }
  for (let i = 0; i < root.allOccurrences.count; i++) {
    const occurrence = root.allOccurrences.item(i);
    for (let j = 0; j < occurrence.bRepBodies.count; j++) {
      const r = record(occurrence.bRepBodies.item(j)); if (r) bodies.push(r);
    }
  }
  if (!bodies.length) throw Error("STEP did not produce coloured BRep solids");
  writeFileSync("colors.json", JSON.stringify({ schema_version: 1, bodies }));
  const exportOptions = design.exportManager.createSATExportOptions("outputFile.sat");
  if (!exportOptions || !design.exportManager.execute(exportOptions)) {
    throw Error("SAT export failed");
  }
  while (app.hasActiveJobs) {
    const until = Date.now() + 2000;
    while (Date.now() < until) adsk.doEvents();
  }
  adsk.result = JSON.stringify({ message: "SAT and body colour manifest exported", bodies: bodies.length });
}

run();
