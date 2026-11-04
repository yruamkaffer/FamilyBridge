import { adsk } from "@adsk/fas";
import { readFileSync, writeFileSync } from "fs";

function waitForJobs(app: adsk.core.Application) {
  const deadline = Date.now() + 420000;
  while (app.hasActiveJobs) {
    if (Date.now() > deadline) throw Error("Timed out waiting for Fusion SAT export");
    adsk.doEvents();
  }
}

function writeUInt32LE(bytes: Uint8Array, offset: number, value: number) {
  bytes[offset] = value & 255;
  bytes[offset + 1] = (value >>> 8) & 255;
  bytes[offset + 2] = (value >>> 16) & 255;
  bytes[offset + 3] = (value >>> 24) & 255;
}

function satHeader(bytes: Uint8Array): string {
  let header = "";
  for (let i = 0; i < Math.min(40, bytes.length); i++) header += String.fromCharCode(bytes[i]);
  return header;
}

function containsBody(bytes: Uint8Array): boolean {
  for (let i = 0; i + 4 < bytes.length; i++) {
    if (bytes[i] === 98 && bytes[i + 1] === 111 && bytes[i + 2] === 100 &&
        bytes[i + 3] === 121 && bytes[i + 4] === 32) return true;
  }
  return false;
}

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
           min_mm: [box.minPoint.x, box.minPoint.y, box.minPoint.z].map(v => v * 10),
           max_mm: [box.maxPoint.x, box.maxPoint.y, box.maxPoint.z].map(v => v * 10),
           volume_mm3: body.physicalProperties.volume * 1000, rgb };
}

// Exporting a component writes its own local coordinate system. A body moved
// with createComponent() can acquire a rotated occurrence; exporting just its
// component then loses that occurrence transform. Put every body in a new
// component whose occurrence is identity in the root assembly instead.
function assertSameAssemblyBox(before: NonNullable<ReturnType<typeof record>>,
                               after: NonNullable<ReturnType<typeof record>>, index: number) {
  const original = [...before.min_mm, ...before.max_mm];
  const isolated = [...after.min_mm, ...after.max_mm];
  const delta = Math.max(...original.map((v, j) => Math.abs(v - isolated[j])));
  const volumeDelta = Math.abs(before.volume_mm3 - after.volume_mm3) / before.volume_mm3;
  // Fusion's boundingBox is an envelope of curved faces. Moving the same
  // BRep into another component can vary this envelope by a few millimetres
  // without changing the solid (observed: 1.565 mm, volume 0.000%). A rotated
  // occurrence in the previous exporter differed by tens of millimetres.
  console.log(`Body ${index}: isolation box delta ${delta.toFixed(3)} mm; ` +
              `volume delta ${(volumeDelta * 100).toFixed(3)}%`);
  if (!Number.isFinite(delta) || delta >= 5.0 || !Number.isFinite(volumeDelta) || volumeDelta > 0.001) {
    throw Error(`Body ${index}: isolation changed its position/orientation ` +
                `(box ${delta.toFixed(3)} mm, volume ${(volumeDelta * 100).toFixed(3)}%).`);
  }
}

function run() {
  const app = adsk.core.Application.get();
  if (!app) throw Error("Fusion Application unavailable");

  const options = app.importManager.createSTEPImportOptions("inputFile.step");
  const document = app.importManager.importToNewDocument(options);
  if (!document) throw Error("STEP import failed");
  const design = document.products.itemByProductType("DesignProductType") as adsk.fusion.Design;
  if (!design) throw Error("STEP did not produce a Fusion design");
  const bodies: NonNullable<ReturnType<typeof record>>[] = [];
  const sources: adsk.fusion.BRepBody[] = [];
  const root = design.rootComponent;
  for (let i = 0; i < root.bRepBodies.count; i++) {
    const body = root.bRepBodies.item(i);
    const r = record(body); if (r) { bodies.push(r); sources.push(body); }
  }
  for (let i = 0; i < root.allOccurrences.count; i++) {
    const occurrence = root.allOccurrences.item(i);
    for (let j = 0; j < occurrence.bRepBodies.count; j++) {
      const body = occurrence.bRepBodies.item(j);
      const r = record(body); if (r) { bodies.push(r); sources.push(body); }
    }
  }
  if (!bodies.length) throw Error("STEP did not produce coloured BRep solids");
  const exportOptions = design.exportManager.createSATExportOptions("outputFile.sat");
  if (!exportOptions || !design.exportManager.execute(exportOptions)) {
    throw Error("SAT export failed");
  }
  waitForJobs(app);
  // Revit merges bodies when a complete SAT is imported as one 3D shape.
  // Copy each source body into an identity occurrence in the root component
  // and export that component. Some imported STEP bodies trigger a Fusion
  // cut_raw() validation error while moving, so only try move if copy fails.
  // Both API operations preserve assembly-space position; verify it below.
  // The order here is the same as the colour manifest, so geometry and RGB
  // remain paired even when several bodies share the same generic name.
  if (sources.length > 256) throw Error("Too many solid bodies (maximum 256)");
  const chunks: Uint8Array[] = [];
  const header = new Uint8Array([70, 66, 66, 49, 0, 0, 0, 0]);
  writeUInt32LE(header, 4, sources.length);
  chunks.push(header);
  let totalSize = header.length;
  const stepChunks: Uint8Array[] = [];
  const stepHeader = new Uint8Array([70, 66, 83, 49, 0, 0, 0, 0]);
  writeUInt32LE(stepHeader, 4, sources.length);
  stepChunks.push(stepHeader);
  let stepTotalSize = stepHeader.length;
  for (let i = 0; i < sources.length; i++) {
    console.log(`Isolating body ${i + 1}/${sources.length}: ${bodies[i].name}`);
    const occurrence = root.occurrences.addNewComponent(adsk.core.Matrix3D.create());
    if (!occurrence) throw Error(`Cannot create identity occurrence for body ${i + 1}`);
    let isolatedBody: adsk.fusion.BRepBody | null = null;
    try {
      isolatedBody = sources[i].copyToComponent(occurrence);
    } catch (error) {
      console.log(`Body ${i + 1}: copyToComponent failed: ${String(error)}`);
    }
    if (!isolatedBody) {
      console.log(`Body ${i + 1}: trying moveToComponent fallback`);
      try {
        isolatedBody = sources[i].moveToComponent(occurrence);
      } catch (error) {
        throw Error(`Body ${i + 1}: copy and move isolation failed: ${String(error)}`);
      }
    }
    if (!isolatedBody) throw Error(`Cannot isolate solid body ${i + 1} into a component`);
    const isolated = record(isolatedBody);
    if (!isolated) throw Error(`Body ${i + 1} ceased to be solid during isolation`);
    assertSameAssemblyBox(bodies[i], isolated, i + 1);
    const filename = `part-${String(i + 1).padStart(4, "0")}.sat`;
    const part = design.exportManager.createSATExportOptions(filename, isolatedBody.parentComponent);
    if (!part || !design.exportManager.execute(part)) throw Error(`SAT export failed for solid body ${i + 1}`);
    waitForJobs(app);
    const bytes = readFileSync(filename);
    if (!/^\s*[1-9]\d*\s/.test(satHeader(bytes)) || !containsBody(bytes)) {
      throw Error(`Invalid SAT for solid body ${i + 1}`);
    }
    const length = new Uint8Array(4);
    writeUInt32LE(length, 0, bytes.length);
    totalSize += length.length + bytes.length;
    if (totalSize > 100 * 1024 * 1024) throw Error("Isolated SAT archive exceeds 100 MB");
    chunks.push(length, bytes);

    // Revit 2024.3 can import STEP directly when ACIS yields no usable Solid.
    // Export from the same isolated component to retain exact manifest order.
    const stepName = `part-${String(i + 1).padStart(4, "0")}.step`;
    const step = design.exportManager.createSTEPExportOptions(stepName, isolatedBody.parentComponent);
    if (!step || !design.exportManager.execute(step)) throw Error(`STEP export failed for solid body ${i + 1}`);
    waitForJobs(app);
    const stepBytes = readFileSync(stepName);
    if (!satHeader(stepBytes).startsWith("ISO-10303-21;")) throw Error(`Invalid STEP for solid body ${i + 1}`);
    const stepLength = new Uint8Array(4);
    writeUInt32LE(stepLength, 0, stepBytes.length);
    stepTotalSize += stepLength.length + stepBytes.length;
    if (stepTotalSize > 100 * 1024 * 1024) throw Error("Isolated STEP archive exceeds 100 MB");
    stepChunks.push(stepLength, stepBytes);
  }
  const archive = new Uint8Array(totalSize);
  let position = 0;
  for (const chunk of chunks) {
    archive.set(chunk, position);
    position += chunk.length;
  }
  writeFileSync("bodies.fbdat", archive);
  const stepArchive = new Uint8Array(stepTotalSize);
  let stepPosition = 0;
  for (const chunk of stepChunks) {
    stepArchive.set(chunk, stepPosition);
    stepPosition += chunk.length;
  }
  writeFileSync("steps.fbdat", stepArchive);
  writeFileSync("colors.json", JSON.stringify({ schema_version: 1,
    isolation_coordinates: "assembly_mm", bodies }));
  waitForJobs(app);
  adsk.result = JSON.stringify({ message: "Isolated SAT and STEP bodies with RGB manifest exported", bodies: bodies.length });
}

run();
