// FamilyBridge Revit 2024 APS — compilar contra referências Revit 2024 e validar na APS.
// Autor: Yruam Käffer de Faria (2026)
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using Autodesk.Revit.ApplicationServices;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using DesignAutomationFramework;

namespace YruamKaffer.FamilyBridge.Automation
{
    [Transaction(TransactionMode.Manual)]
    [Regeneration(RegenerationOption.Manual)]
    public class FamilyBridgeApp : IExternalDBApplication
    {
        // Os arquivos são entregues pelo WorkItem no diretório de trabalho da APS.
        private const string BodyArchiveFile = "bodies.fbdat";
        private const string StepArchiveFile = "steps.fbdat";
        private const string MetadataFile = "metadata.json";
        private const string ColorsFile = "colors.json";
        private const string TemplateFile = "template.rft";
        private const string OutputFile = "output.rfa";

        public ExternalDBApplicationResult OnStartup(ControlledApplication application)
        {
            DesignAutomationBridge.DesignAutomationReadyEvent += OnReady;
            return ExternalDBApplicationResult.Succeeded;
        }

        public ExternalDBApplicationResult OnShutdown(ControlledApplication application)
        {
            DesignAutomationBridge.DesignAutomationReadyEvent -= OnReady;
            return ExternalDBApplicationResult.Succeeded;
        }

        private void OnReady(object sender, DesignAutomationReadyEventArgs e)
        {
            try
            {
                Run(e.DesignAutomationData.RevitApp);
                e.Succeeded = true;
                Console.WriteLine("[FamilyBridge] output.rfa criado.");
            }
            catch (Exception ex)
            {
                Console.WriteLine("[FamilyBridge] FALHA: " + ex);
                e.Succeeded = false;
            }
        }

        private static void Run(Application app)
        {
            Console.WriteLine("[FamilyBridge] worker 0.9.5 solid-first STEP retry RGB; engine Revit " + app.VersionNumber);
            if (app.VersionNumber != "2024") throw new InvalidOperationException("O conversor exige engine Revit 2024.");
            string workDir = Directory.GetCurrentDirectory();
            string archivePath = Path.Combine(workDir, BodyArchiveFile);
            string stepArchivePath = Path.Combine(workDir, StepArchiveFile);
            string templatePath = Path.Combine(workDir, TemplateFile);
            string metaPath = Path.Combine(workDir, MetadataFile);
            string colorsPath = Path.Combine(workDir, ColorsFile);
            string outputPath = Path.Combine(workDir, OutputFile);
            foreach (string path in new[] { archivePath, stepArchivePath, templatePath, metaPath, colorsPath })
                if (!File.Exists(path)) throw new FileNotFoundException("Entrada ausente", path);

            Metadata root;
            using (FileStream stream = File.OpenRead(metaPath))
            {
                var serializer = new DataContractJsonSerializer(typeof(Metadata),
                    new DataContractJsonSerializerSettings { UseSimpleDictionaryFormat = true });
                root = (Metadata)serializer.ReadObject(stream);
            }
            if (root == null || root.SchemaVersion != 1 || root.Product == null)
                throw new InvalidDataException("metadata.json inválido: schema_version ou product inválido.");

            if (string.IsNullOrWhiteSpace(Read(root.Product, "code")) ||
                string.IsNullOrWhiteSpace(Read(root.Product, "name")))
                throw new InvalidDataException("Código e nome do produto são obrigatórios.");

            ColorManifest colors;
            using (FileStream stream = File.OpenRead(colorsPath))
                colors = (ColorManifest)new DataContractJsonSerializer(typeof(ColorManifest)).ReadObject(stream);
            if (colors == null || colors.SchemaVersion != 1 || colors.Bodies == null || colors.Bodies.Count == 0)
                throw new InvalidDataException("Manifesto de cores ausente ou inválido.");
            string[] satParts = ReadBodyArchive(archivePath, workDir, colors.Bodies.Count);
            string[] stepParts = ReadStepArchive(stepArchivePath, workDir, colors.Bodies.Count);

            // NewFamilyDocument exige um modelo .rft válido compatível com Revit 2024 (templates anteriores podem ser atualizados).
            Document family = app.NewFamilyDocument(templatePath);
            if (family == null || !family.IsFamilyDocument)
                throw new InvalidOperationException("Não foi possível criar o documento da família.");

            try
            {
                using (Transaction tx = new Transaction(family, "FamilyBridge: geometria e parâmetros"))
                {
                    if (tx.Start() != TransactionStatus.Started)
                        throw new InvalidOperationException("Não foi possível iniciar transação.");
                    SetCategory(family, Read(root.Product, "category"));
                    View targetView = new FilteredElementCollector(family)
                        .OfClass(typeof(View3D)).Cast<View3D>().FirstOrDefault(v => !v.IsTemplate);
                    if (targetView == null)
                    {
                        ViewFamilyType viewType = new FilteredElementCollector(family)
                            .OfClass(typeof(ViewFamilyType)).Cast<ViewFamilyType>()
                            .FirstOrDefault(t => t.ViewFamily == ViewFamily.ThreeDimensional);
                        if (viewType == null) throw new InvalidOperationException("Template sem ViewFamilyType 3D.");
                        targetView = View3D.CreateIsometric(family, viewType.Id);
                    }

                    var materialCache = new Dictionary<string, ElementId>();
                    var geometryDifferences = new List<string>();
                    var meshBodies = new List<int>();
                    for (int i = 0; i < satParts.Length; i++)
                    {
                        ElementId importId = family.Import(satParts[i], new SATImportOptions(), targetView);
                        if (importId == ElementId.InvalidElementId)
                            throw new InvalidOperationException("SAT individual não importado: corpo " + (i + 1));
                        Element imported = family.GetElement(importId);
                        if (imported == null) throw new InvalidOperationException("Importação sem elemento: corpo " + (i + 1));
                        var solids = new List<Solid>();
                        bool stepImported = false;
                        double? satVolumeMm3 = null;
                        double[] satDimensionsMm = null;
                        CollectSolids(imported.get_Geometry(new Options { ComputeReferences = true }), solids);
                        Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) + ": sólidos Revit = " + solids.Count);
                        if (solids.Count != 1)
                        {
                            Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) + ": SAT gerou " + solids.Count +
                                " sólidos; tentando STEP individual.");
                            family.Delete(importId);
                            importId = family.Import(stepParts[i], new STEPImportOptions(), targetView);
                            stepImported = true;
                            if (importId == ElementId.InvalidElementId)
                                throw new InvalidOperationException("STEP individual não importado: corpo " + (i + 1));
                            imported = family.GetElement(importId);
                            if (imported == null) throw new InvalidOperationException("STEP importado sem elemento: corpo " + (i + 1));
                            solids.Clear();
                            CollectSolids(imported.get_Geometry(new Options { ComputeReferences = true }), solids);
                            Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) + ": sólidos Revit via STEP = " + solids.Count);
                            if (solids.Count != 1)
                            {
                                Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) +
                                    ": geometria importada do STEP:");
                                DescribeGeometry(imported.get_Geometry(new Options { ComputeReferences = true }), 0);
                                // ShapeImporter is a separate Revit conversion path for SAT.
                                // Accept only a real positive-volume Solid; never silently
                                // substitute a mesh for a FreeFormElement.
                                try
                                {
                                    var shapeImporter = new ShapeImporter();
                                    shapeImporter.InputFormat = ShapeImporterSourceFormat.SAT;
                                    IList<GeometryObject> converted = shapeImporter.Convert(family, satParts[i]);
                                    Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) +
                                        ": ShapeImporter devolveu " + converted.Count + " objetos.");
                                    foreach (GeometryObject obj in converted)
                                    {
                                        Solid candidate = obj as Solid;
                                        if (candidate != null)
                                            Console.WriteLine("[FamilyBridge] ShapeImporter Solid faces=" + candidate.Faces.Size +
                                                " volume=" + candidate.Volume.ToString("G6", System.Globalization.CultureInfo.InvariantCulture));
                                        else
                                            Console.WriteLine("[FamilyBridge] ShapeImporter tipo=" + obj.GetType().Name);
                                    }
                                    solids.Clear();
                                    solids.AddRange(converted.OfType<Solid>().Where(s => s.Faces.Size > 0 && s.Volume > 0));
                                }
                                catch (Exception ex)
                                {
                                    Console.WriteLine("[FamilyBridge] ShapeImporter falhou: " + ex.GetType().Name + ": " + ex.Message);
                                    solids.Clear();
                                }
                                if (solids.Count != 1)
                                {
                                    var meshes = new List<Mesh>();
                                    CollectMeshes(imported.get_Geometry(new Options { ComputeReferences = true }), meshes);
                                    if (meshes.Count != 1)
                                        throw new InvalidDataException("Corpo " + (i + 1) +
                                            " sem sólido e com " + meshes.Count + " malhas STEP; correspondência ambígua.");
                                    CreateMeshFallback(family, meshes[0], colors.Bodies[i], materialCache, i + 1);
                                    meshBodies.Add(i + 1);
                                    family.Delete(importId);
                                    continue;
                                }
                                Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) + ": sólido recuperado via ShapeImporter SAT.");
                            }
                        }
                    validateSolid:
                        Solid solid = solids[0];
                        ColorBody matched = colors.Bodies[i];
                        // Solid bounds are local coordinates plus a transform, not world bounds.
                        XYZ worldMin, worldMax;
                        WorldBounds(solid, out worldMin, out worldMax);
                        double[] dims = new[] {worldMax.X - worldMin.X, worldMax.Y - worldMin.Y, worldMax.Z - worldMin.Z};
                        double[] sorted = dims.Select(v => v * 304.8).OrderBy(v => v).ToArray();
                        double volume = solid.Volume * 304.8 * 304.8 * 304.8;
                        Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) + ": volume mm3 = " +
                            volume.ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
                        Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) + ": dimensões Revit mm = " +
                            string.Join(", ", dims.Select(v => (v * 304.8).ToString("F3", System.Globalization.CultureInfo.InvariantCulture))) +
                            "; Fusion mm = " + (matched.DimensionsMm == null ? "ausente" :
                            string.Join(", ", matched.DimensionsMm.Select(v => v.ToString("F3", System.Globalization.CultureInfo.InvariantCulture)))));
                        if (matched.MinMm == null || matched.MaxMm == null ||
                            matched.MinMm.Length != 3 || matched.MaxMm.Length != 3 ||
                            matched.DimensionsMm == null || matched.DimensionsMm.Length != 3 ||
                            matched.VolumeMm3 <= 0)
                            throw new InvalidDataException("Geometria ou posição do corpo " + (i + 1) + " ausente no manifesto.");
                        // SAT import may enlarge the API's enclosing box without a
                        // comparable change in volume. The SAT archive already pairs
                        // one isolated solid with this manifest entry by its index.
                        double volumeDifference = Math.Abs(matched.VolumeMm3 - volume) / matched.VolumeMm3;
                        double largestDimensionDifference = matched.DimensionsMm.Zip(sorted,
                            (expected, actual) => Math.Abs(expected - actual)).Max();
                        double largestAxisDifference = Enumerable.Range(0, 3).Max(axis =>
                            Math.Abs(dims[axis] * 304.8 - (matched.MaxMm[axis] - matched.MinMm[axis])));
                        Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) + ": desvio volume = " +
                            (volumeDifference * 100).ToString("F3", System.Globalization.CultureInfo.InvariantCulture) +
                            "%; desvio máximo dimensão/eixo mm = " +
                            Math.Max(largestDimensionDifference, largestAxisDifference).ToString("F3", System.Globalization.CultureInfo.InvariantCulture));
                        if (double.IsNaN(volumeDifference) || double.IsInfinity(volumeDifference) ||
                            double.IsNaN(largestDimensionDifference) || double.IsInfinity(largestDimensionDifference) ||
                            double.IsNaN(largestAxisDifference) || double.IsInfinity(largestAxisDifference) ||
                            volumeDifference >= 0.02 || largestDimensionDifference >= 5.0 || largestAxisDifference >= 5.0)
                        {
                            if (!stepImported)
                            {
                                // A SAT can look like a solid yet fail the geometry check.
                                // Try the paired STEP before rejecting this body or accepting
                                // an inaccurate SAT volume. The original import is removed.
                                Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) +
                                    ": sólido SAT fora da tolerância; tentando STEP individual.");
                                satVolumeMm3 = volume;
                                satDimensionsMm = dims.Select(v => v * 304.8).ToArray();
                                family.Delete(importId);
                                importId = family.Import(stepParts[i], new STEPImportOptions(), targetView);
                                if (importId == ElementId.InvalidElementId)
                                    throw new InvalidOperationException("STEP individual não importado: corpo " + (i + 1));
                                imported = family.GetElement(importId);
                                if (imported == null)
                                    throw new InvalidOperationException("STEP importado sem elemento: corpo " + (i + 1));
                                stepImported = true;
                                solids.Clear();
                                CollectSolids(imported.get_Geometry(new Options { ComputeReferences = true }), solids);
                                Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) +
                                    ": sólidos Revit via STEP após desvio SAT = " + solids.Count);
                                if (solids.Count == 1) goto validateSolid;
                                var alternateMeshes = new List<Mesh>();
                                CollectMeshes(imported.get_Geometry(new Options { ComputeReferences = true }), alternateMeshes);
                                if (alternateMeshes.Count == 1)
                                {
                                    CreateMeshFallback(family, alternateMeshes[0], matched, materialCache, i + 1);
                                    meshBodies.Add(i + 1);
                                    family.Delete(importId);
                                    continue;
                                }
                                Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) +
                                    ": STEP alternativo sem sólido único ou malha única.");
                            }
                            // Revit can approximate Solid.Volume on curved surfaces. The
                            // Fusion manifest has already validated the isolated source.
                            // Only accept a bounded discrepancy if two independent Revit
                            // imports produce effectively the same positive-volume solid.
                            double boundError = Math.Max(largestDimensionDifference, largestAxisDifference);
                            bool formatsAgree = satVolumeMm3.HasValue && satDimensionsMm != null &&
                                Math.Abs(satVolumeMm3.Value - volume) / matched.VolumeMm3 < 0.001 &&
                                satDimensionsMm.Zip(dims, (sat, step) => Math.Abs(sat - step * 304.8)).Max() < 0.2;
                            if (stepImported && formatsAgree && volumeDifference < 0.04 && boundError < 2.0)
                            {
                                Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) +
                                    ": exceção controlada de volume Revit; SAT e STEP concordam, desvio " +
                                    (volumeDifference * 100).ToString("F3", System.Globalization.CultureInfo.InvariantCulture) +
                                    "%, caixa " + boundError.ToString("F3", System.Globalization.CultureInfo.InvariantCulture) + " mm.");
                            }
                            else
                            {
                                geometryDifferences.Add("corpo " + (i + 1) + " (volume " +
                                    (volumeDifference * 100).ToString("F2", System.Globalization.CultureInfo.InvariantCulture) +
                                    "%, caixa " + boundError.ToString("F2", System.Globalization.CultureInfo.InvariantCulture) + " mm)");
                                family.Delete(importId);
                                continue;
                            }
                        }
                        XYZ currentCenter = (worldMin + worldMax) * 0.5;
                        XYZ desiredCenter = new XYZ(
                            (matched.MinMm[0] + matched.MaxMm[0]) / 609.6,
                            (matched.MinMm[1] + matched.MaxMm[1]) / 609.6,
                            (matched.MinMm[2] + matched.MaxMm[2]) / 609.6);
                        XYZ offset = desiredCenter - currentCenter;
                        if (offset.GetLength() > 1e-8)
                            solid = SolidUtils.CreateTransformed(solid, Transform.CreateTranslation(offset));
                        Console.WriteLine("[FamilyBridge] Corpo " + (i + 1) + ": deslocamento mm = " +
                            string.Join(", ", new[] {offset.X, offset.Y, offset.Z}.Select(v =>
                                (v * 304.8).ToString("F3", System.Globalization.CultureInfo.InvariantCulture))));
                        FreeFormElement element = FreeFormElement.Create(family, solid);
                        if (matched.Rgb != null)
                        {
                            if (matched.Rgb.Length != 3 || matched.Rgb.Any(v => v < 0 || v > 255))
                                throw new InvalidDataException("RGB inválido no corpo " + (i + 1));
                            string key = string.Join("-", matched.Rgb);
                            ElementId materialId;
                            if (!materialCache.TryGetValue(key, out materialId))
                            {
                                materialId = Material.Create(family, "FamilyBridge RGB " + key);
                                Material material = (Material)family.GetElement(materialId);
                                material.Color = new Autodesk.Revit.DB.Color((byte)matched.Rgb[0], (byte)matched.Rgb[1], (byte)matched.Rgb[2]);
                                materialCache.Add(key, materialId);
                            }
                            Parameter materialParameter = element.get_Parameter(BuiltInParameter.MATERIAL_ID_PARAM);
                            if (materialParameter == null || materialParameter.IsReadOnly || !materialParameter.Set(materialId))
                                throw new InvalidOperationException("O sólido " + (i + 1) + " não aceitou material RGB.");
                        }
                        family.Delete(importId);
                    }
                    if (geometryDifferences.Count > 0)
                        throw new InvalidDataException("Geometria SAT/Revit fora da tolerância: " + string.Join("; ", geometryDifferences));
                    Console.WriteLine("[FamilyBridge] FreeFormElements sólidos criados: " + (satParts.Length - meshBodies.Count) +
                        "; corpos em malha: " + meshBodies.Count +
                        (meshBodies.Count == 0 ? "" : " (" + string.Join(", ", meshBodies) + ")"));

                    FamilyManager fm = family.FamilyManager;
                    if (fm.CurrentType == null)
                    {
                        string typeName = Read(root.Product, "code");
                        if (string.IsNullOrWhiteSpace(typeName)) typeName = "FamilyBridge_Type";
                        fm.NewType(typeName);
                    }
                    SetBuiltinIfAvailable(fm, BuiltInParameter.ALL_MODEL_MANUFACTURER, Read(root.Product, "manufacturer"));
                    SetBuiltinIfAvailable(fm, BuiltInParameter.ALL_MODEL_MODEL, Read(root.Product, "code"));
                    SetBuiltinIfAvailable(fm, BuiltInParameter.ALL_MODEL_URL, Read(root.Product, "website"));
                    SetBuiltinIfAvailable(fm, BuiltInParameter.ALL_MODEL_DESCRIPTION, Read(root.Product, "description"));
                    var mapping = new Dictionary<string, string>
                    {
                        { "FB_Fabricante", "manufacturer" }, { "FB_Codigo", "code" },
                        { "FB_Produto", "name" }, { "FB_Linha", "collection" },
                        { "FB_Acabamento", "finish" }, { "FB_Descricao", "description" },
                        { "FB_Site", "website" }
                    };
                    foreach (var item in mapping)
                        SetTextParameter(fm, item.Key, Read(root.Product, item.Value));
                    if (tx.Commit() != TransactionStatus.Committed)
                        throw new InvalidOperationException("Revit não confirmou a transação da família.");
                }
                if (File.Exists(outputPath)) File.Delete(outputPath);
                string outputName = Path.GetFileNameWithoutExtension(root.OutputName ?? "");
                if (string.IsNullOrWhiteSpace(outputName) || outputName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
                    !string.Equals(Path.GetFileName(root.OutputName), root.OutputName, StringComparison.Ordinal) ||
                    !root.OutputName.EndsWith(".rfa", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("Nome da família inválido.");
                string titledPath = Path.Combine(workDir, root.OutputName);
                family.SaveAs(titledPath, new SaveAsOptions { OverwriteExistingFile = true });
                if (!string.Equals(titledPath, outputPath, StringComparison.OrdinalIgnoreCase))
                    File.Copy(titledPath, outputPath, true);
                if (!File.Exists(outputPath) || new FileInfo(outputPath).Length == 0)
                    throw new IOException("Revit não produziu output.rfa válido.");
            }
            finally
            {
                family.Close(false);
            }
        }

        private static void WorldBounds(Solid solid, out XYZ minimum, out XYZ maximum)
        {
            BoundingBoxXYZ box = solid.GetBoundingBox();
            if (box == null || box.Transform == null)
                throw new InvalidDataException("Sólido sem limites geométricos.");
            var points = new List<XYZ>(8);
            foreach (double x in new[] { box.Min.X, box.Max.X })
                foreach (double y in new[] { box.Min.Y, box.Max.Y })
                    foreach (double z in new[] { box.Min.Z, box.Max.Z })
                        points.Add(box.Transform.OfPoint(new XYZ(x, y, z)));
            minimum = new XYZ(points.Min(p => p.X), points.Min(p => p.Y), points.Min(p => p.Z));
            maximum = new XYZ(points.Max(p => p.X), points.Max(p => p.Y), points.Max(p => p.Z));
        }

        private static void CollectSolids(GeometryElement geometry, List<Solid> solids)
        {
            if (geometry == null) return;
            foreach (GeometryObject item in geometry)
            {
                Solid solid = item as Solid;
                if (solid != null && solid.Faces.Size > 0 && solid.Volume > 0)
                {
                    solids.Add(solid);
                    continue;
                }
                GeometryInstance instance = item as GeometryInstance;
                if (instance != null)
                    CollectSolids(instance.GetInstanceGeometry(), solids);
            }
        }

        private static void CollectMeshes(GeometryElement geometry, List<Mesh> meshes)
        {
            if (geometry == null) return;
            foreach (GeometryObject item in geometry)
            {
                Mesh mesh = item as Mesh;
                if (mesh != null && mesh.NumTriangles > 0) meshes.Add(mesh);
                GeometryInstance instance = item as GeometryInstance;
                if (instance != null) CollectMeshes(instance.GetInstanceGeometry(), meshes);
            }
        }

        private static void CreateMeshFallback(Document family, Mesh mesh, ColorBody matched,
            Dictionary<string, ElementId> materials, int number)
        {
            if (matched.MinMm == null || matched.MaxMm == null || matched.DimensionsMm == null ||
                matched.MinMm.Length != 3 || matched.MaxMm.Length != 3 || matched.DimensionsMm.Length != 3 ||
                matched.VolumeMm3 <= 0 || matched.Rgb == null || matched.Rgb.Length != 3 ||
                matched.Rgb.Any(v => v < 0 || v > 255))
                throw new InvalidDataException("Manifesto geométrico/RGB inválido para malha do corpo " + number);
            if (mesh.NumTriangles > 100000)
                throw new InvalidDataException("Malha do corpo " + number + " excede 100.000 triângulos.");
            var vertices = mesh.Vertices.ToList();
            if (vertices.Count < 4) throw new InvalidDataException("Malha vazia no corpo " + number);
            XYZ minimum = new XYZ(vertices.Min(v => v.X), vertices.Min(v => v.Y), vertices.Min(v => v.Z));
            XYZ maximum = new XYZ(vertices.Max(v => v.X), vertices.Max(v => v.Y), vertices.Max(v => v.Z));
            double[] dimensions = { maximum.X - minimum.X, maximum.Y - minimum.Y, maximum.Z - minimum.Z };
            double[] sorted = dimensions.Select(d => d * 304.8).OrderBy(d => d).ToArray();
            double dimensionError = matched.DimensionsMm.Zip(sorted, (a, b) => Math.Abs(a - b)).Max();
            double axisError = Enumerable.Range(0, 3).Max(axis =>
                Math.Abs(dimensions[axis] * 304.8 - (matched.MaxMm[axis] - matched.MinMm[axis])));
            // Oriented triangle volume detects open or corrupt tessellations.
            XYZ center = (minimum + maximum) * 0.5;
            double sixVolume = 0;
            for (int i = 0; i < mesh.NumTriangles; i++)
            {
                MeshTriangle t = mesh.get_Triangle(i);
                XYZ a = t.get_Vertex(0) - center;
                XYZ b = t.get_Vertex(1) - center;
                XYZ c = t.get_Vertex(2) - center;
                sixVolume += a.DotProduct(b.CrossProduct(c));
            }
            double volumeMm3 = Math.Abs(sixVolume) / 6.0 * 304.8 * 304.8 * 304.8;
            double volumeError = Math.Abs(volumeMm3 - matched.VolumeMm3) / matched.VolumeMm3;
            Console.WriteLine("[FamilyBridge] Corpo " + number + ": malha triângulos=" + mesh.NumTriangles +
                " volume mm3=" + volumeMm3.ToString("F3", System.Globalization.CultureInfo.InvariantCulture) +
                " desvio volume=" + (volumeError * 100).ToString("F2", System.Globalization.CultureInfo.InvariantCulture) +
                "% desvio dimensões=" + Math.Max(dimensionError, axisError).ToString("F3", System.Globalization.CultureInfo.InvariantCulture) + " mm");
            if (double.IsNaN(volumeError) || double.IsInfinity(volumeError) || volumeError >= 0.02 ||
                double.IsNaN(dimensionError) || double.IsInfinity(dimensionError) ||
                Math.Max(dimensionError, axisError) >= 5.0)
                throw new InvalidDataException("Corpo " + number + ": malha fora da tolerância de volume/dimensões.");
            XYZ expectedCenter = new XYZ((matched.MinMm[0] + matched.MaxMm[0]) / 609.6,
                (matched.MinMm[1] + matched.MaxMm[1]) / 609.6,
                (matched.MinMm[2] + matched.MaxMm[2]) / 609.6);
            XYZ displacement = expectedCenter - center;
            string key = string.Join("-", matched.Rgb);
            ElementId materialId;
            if (!materials.TryGetValue(key, out materialId))
            {
                materialId = Material.Create(family, "FamilyBridge RGB " + key);
                Material material = (Material)family.GetElement(materialId);
                material.Color = new Autodesk.Revit.DB.Color((byte)matched.Rgb[0],
                    (byte)matched.Rgb[1], (byte)matched.Rgb[2]);
                materials.Add(key, materialId);
            }
            var builder = new TessellatedShapeBuilder();
            builder.OpenConnectedFaceSet(true);
            for (int i = 0; i < mesh.NumTriangles; i++)
            {
                MeshTriangle t = mesh.get_Triangle(i);
                var face = new TessellatedFace(new[] {
                    t.get_Vertex(0) + displacement,
                    t.get_Vertex(1) + displacement,
                    t.get_Vertex(2) + displacement }, materialId);
                builder.AddFace(face);
            }
            builder.CloseConnectedFaceSet();
            builder.Target = TessellatedShapeBuilderTarget.Mesh;
            builder.Fallback = TessellatedShapeBuilderFallback.Salvage;
            builder.Build();
            IList<GeometryObject> geometry = builder.GetBuildResult().GetGeometricalObjects();
            if (geometry.Count != 1 || !(geometry[0] is Mesh))
                throw new InvalidDataException("Malha reconstruída do corpo " + number + " inválida.");
            ElementId categoryId = family.OwnerFamily.FamilyCategory.Id;
            if (!DirectShape.IsSupportedDocument(family) || !DirectShape.IsValidCategoryId(categoryId, family))
                throw new InvalidOperationException("A categoria da família não aceita DirectShape para o corpo " + number);
            DirectShape element = DirectShape.CreateElement(family, categoryId);
            element.ApplicationId = "FamilyBridge";
            element.ApplicationDataId = "body-" + number;
            element.SetShape(geometry);
            Console.WriteLine("[FamilyBridge] Corpo " + number + ": DirectShape Mesh RGB criado; deslocamento mm=" +
                string.Join(", ", new[] {displacement.X, displacement.Y, displacement.Z}.Select(v =>
                    (v * 304.8).ToString("F3", System.Globalization.CultureInfo.InvariantCulture))));
        }

        private static void DescribeGeometry(GeometryElement geometry, int depth)
        {
            if (geometry == null) { Console.WriteLine("[FamilyBridge] geometria nula"); return; }
            if (depth > 3) return;
            int count = 0;
            foreach (GeometryObject item in geometry)
            {
                if (++count > 20) { Console.WriteLine("[FamilyBridge] mais objetos omitidos"); break; }
                Solid s = item as Solid;
                Mesh mesh = item as Mesh;
                Console.WriteLine("[FamilyBridge] geometria nível=" + depth + " tipo=" + item.GetType().Name +
                    (s == null ? "" : " faces=" + s.Faces.Size + " volume=" + s.Volume.ToString("G6", System.Globalization.CultureInfo.InvariantCulture)) +
                    (mesh == null ? "" : " triângulos=" + mesh.NumTriangles));
                GeometryInstance nested = item as GeometryInstance;
                if (nested != null) DescribeGeometry(nested.GetInstanceGeometry(), depth + 1);
            }
        }

        // FBB1/FBS1: ASCII magic, UInt32LE count, then UInt32LE length + bytes
        // for each body in the exact order of colors.json. No input file paths.
        private static string[] ReadBodyArchive(string archivePath, string workDir, int expected)
        {
            return ReadGeometryArchive(archivePath, workDir, expected, new byte[] { 70, 66, 66, 49 }, ".sat");
        }

        private static string[] ReadStepArchive(string archivePath, string workDir, int expected)
        {
            return ReadGeometryArchive(archivePath, workDir, expected, new byte[] { 70, 66, 83, 49 }, ".step");
        }

        private static string[] ReadGeometryArchive(string archivePath, string workDir, int expected,
            byte[] magic, string extension)
        {
            using (var stream = File.OpenRead(archivePath))
            using (var reader = new BinaryReader(stream))
            {
                if (stream.Length < 12 || stream.Length > 100 * 1024 * 1024 ||
                    !reader.ReadBytes(4).SequenceEqual(magic))
                    throw new InvalidDataException("Arquivo de corpos " + extension + " inválido.");
                uint count = reader.ReadUInt32();
                if (count != expected || count == 0 || count > 256)
                        throw new InvalidDataException("Número de corpos " + extension + " não corresponde ao manifesto RGB.");
                var files = new string[(int)count];
                for (int i = 0; i < files.Length; i++)
                {
                    if (stream.Length - stream.Position < 4) throw new InvalidDataException("Arquivo de corpos truncado.");
                    uint size = reader.ReadUInt32();
                    if (size < 100 || size > 100 * 1024 * 1024 || stream.Length - stream.Position < size)
                        throw new InvalidDataException("Tamanho inválido no corpo " + (i + 1));
                    byte[] sat = reader.ReadBytes((int)size);
                    string head = System.Text.Encoding.ASCII.GetString(sat, 0, Math.Min(40, sat.Length));
                    if (extension == ".step")
                    {
                        if (!head.StartsWith("ISO-10303-21;", StringComparison.Ordinal))
                            throw new InvalidDataException("STEP inválido no corpo " + (i + 1));
                    }
                    else
                    {
                        int version;
                        string[] tokens = head.Split(new[] { ' ', '\r', '\n', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                        if (tokens.Length == 0 || !int.TryParse(tokens[0], out version) || version < 1 || version > 700)
                            throw new InvalidDataException("Versão SAT incompatível no corpo " + (i + 1));
                    }
                    files[i] = Path.Combine(workDir, "FamilyBridge_part_" + (i + 1) + extension);
                    File.WriteAllBytes(files[i], sat);
                }
                if (stream.Position != stream.Length) throw new InvalidDataException("Dados extras no arquivo de corpos.");
                Console.WriteLine("[FamilyBridge] " + extension + " individuais recebidos: " + files.Length);
                return files;
            }
        }

        private static string Read(Dictionary<string, string> dict, string key)
        {
            string val;
            return dict.TryGetValue(key, out val) ? (val ?? "") : "";
        }

        private static void SetCategory(Document family, string category)
        {
            BuiltInCategory id = BuiltInCategory.OST_GenericModel;
            switch (category)
            {
                case "Plumbing Fixtures": id = BuiltInCategory.OST_PlumbingFixtures; break;
                case "Mechanical Equipment": id = BuiltInCategory.OST_MechanicalEquipment; break;
                case "Furniture": id = BuiltInCategory.OST_Furniture; break;
                case "Generic Models": case "": break;
                default: throw new InvalidDataException("Categoria não suportada: " + category);
            }
            family.OwnerFamily.FamilyCategory = family.Settings.Categories.get_Item(id);
        }

        private static void SetBuiltinIfAvailable(FamilyManager fm, BuiltInParameter builtin, string value)
        {
            try
            {
                FamilyParameter param = fm.get_Parameter(builtin);
                if (param != null && !param.IsReadOnly) fm.Set(param, value);
            }
            catch (Exception ex) { Console.WriteLine("[FamilyBridge] Parâmetro interno indisponível: " + ex.Message); }
        }

        private static void SetTextParameter(FamilyManager fm, string name, string value)
        {
            FamilyParameter param = fm.get_Parameter(name);
            if (param == null)
                param = fm.AddParameter(name, GroupTypeId.IdentityData, SpecTypeId.String.Text, false);
            if (!param.IsReadOnly) fm.Set(param, value ?? "");
        }
    }

    [DataContract]
    public class Metadata
    {
        [DataMember(Name = "schema_version")]
        public int SchemaVersion { get; set; }
        [DataMember(Name = "product")]
        public Dictionary<string, string> Product { get; set; }
        [DataMember(Name = "output_name")]
        public string OutputName { get; set; }
    }

    [DataContract]
    public class ColorManifest
    {
        [DataMember(Name = "schema_version")]
        public int SchemaVersion { get; set; }
        [DataMember(Name = "bodies")]
        public List<ColorBody> Bodies { get; set; }
    }

    [DataContract]
    public class ColorBody
    {
        [DataMember(Name = "dimensions_mm")]
        public double[] DimensionsMm { get; set; }
        [DataMember(Name = "min_mm")]
        public double[] MinMm { get; set; }
        [DataMember(Name = "max_mm")]
        public double[] MaxMm { get; set; }
        [DataMember(Name = "volume_mm3")]
        public double VolumeMm3 { get; set; }
        [DataMember(Name = "rgb")]
        public int[] Rgb { get; set; }
    }
}
