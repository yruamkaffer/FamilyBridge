// FamilyBridge Revit 2024 APS — compilado contra referências Revit 2024; ainda não homologado na APS.
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
        private const string SatFile = "model.sat";
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
            Console.WriteLine("[FamilyBridge] worker 2024 SAT prototype; engine Revit " + app.VersionNumber);
            if (app.VersionNumber != "2024") throw new InvalidOperationException("O conversor exige engine Revit 2024.");
            string workDir = Directory.GetCurrentDirectory();
            string satPath = Path.Combine(workDir, SatFile);
            string templatePath = Path.Combine(workDir, TemplateFile);
            string metaPath = Path.Combine(workDir, MetadataFile);
            string colorsPath = Path.Combine(workDir, ColorsFile);
            string outputPath = Path.Combine(workDir, OutputFile);
            foreach (string path in new[] { satPath, templatePath, metaPath, colorsPath })
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

                    // Extrai os sólidos ACIS e cria elementos nativos FreeFormElement.
                    // A importação SAT temporária é removida para não deixar uma malha/bloco CAD.
                    ElementId importId = family.Import(satPath, new SATImportOptions(), targetView);
                    if (importId == ElementId.InvalidElementId)
                        throw new InvalidOperationException("Revit não importou a geometria SAT.");
                    Element imported = family.GetElement(importId);
                    if (imported == null) throw new InvalidOperationException("Instância SAT ausente após a importação.");
                    List<Solid> solids = new List<Solid>();
                    CollectSolids(imported.get_Geometry(new Options { ComputeReferences = true }), solids);
                    if (solids.Count == 0)
                        throw new InvalidOperationException("SAT importado não contém sólidos BRep utilizáveis; RFA não será criado como malha.");
                    if (solids.Count != colors.Bodies.Count)
                        throw new InvalidDataException("A contagem de sólidos no SAT difere do STEP; cores não serão atribuídas incorretamente.");
                    var unmatched = new List<ColorBody>(colors.Bodies);
                    var materialCache = new Dictionary<string, ElementId>();
                    foreach (Solid solid in solids)
                    {
                        BoundingBoxXYZ box = solid.GetBoundingBox();
                        double[] dimensions = new[] { box.Max.X - box.Min.X,
                            box.Max.Y - box.Min.Y, box.Max.Z - box.Min.Z }
                            .Select(n => n * 304.8).OrderBy(n => n).ToArray();
                        double volume = solid.Volume * 304.8 * 304.8 * 304.8;
                        var candidates = unmatched.Where(b => b.DimensionsMm != null && b.DimensionsMm.Length == 3 &&
                            b.DimensionsMm.Zip(dimensions, (a, c) => Math.Abs(a - c)).Max() < 1.0 &&
                            Math.Abs(b.VolumeMm3 - volume) / Math.Max(volume, 1.0) < 0.02).ToList();
                        if (candidates.Count == 0)
                            throw new InvalidDataException("Não foi possível associar um sólido à sua cor; confira escala e SAT.");
                        if (candidates.Select(b => b.Rgb == null ? "none" : string.Join(",", b.Rgb)).Distinct().Count() > 1)
                            throw new InvalidDataException("Sólidos coincidentes têm cores diferentes; associação ambígua.");
                        ColorBody matched = candidates[0];
                        unmatched.Remove(matched);
                        FreeFormElement element = FreeFormElement.Create(family, solid);
                        if (matched.Rgb != null)
                        {
                            if (matched.Rgb.Length != 3 || matched.Rgb.Any(v => v < 0 || v > 255))
                                throw new InvalidDataException("RGB inválido no manifesto de cores.");
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
                                throw new InvalidOperationException("O sólido não aceitou o material; RFA não será entregue sem cores.");
                        }
                    }
                    family.Delete(importId);
                    Console.WriteLine("[FamilyBridge] FreeFormElements criados: " + solids.Count);

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
        [DataMember(Name = "volume_mm3")]
        public double VolumeMm3 { get; set; }
        [DataMember(Name = "rgb")]
        public int[] Rgb { get; set; }
    }
}
