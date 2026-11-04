# FamilyBridge

**STEP to Revit family, operated from SketchUp through Autodesk Platform Services.**

By **Yruam Kaffer de Faria** · Version **0.9.3** · Interface and full documentation in Portuguese: [README.md](README.md).

FamilyBridge is a SketchUp desktop extension. It collects product metadata, sends a selected solid STEP to Fusion Automation, then creates an RFA through Revit Automation 2024. The resulting family opens in Revit **2024 or later**. Local Revit, Fusion and FreeCAD installations are not required by this workflow. The user must provide an APS application with access to both engines and monitor its quota and billing.

## Install and use

1. Install `FamilyBridge_v0.9.4.rbz` through the SketchUp Extension Manager.
2. Open **FamilyBridge → Configurações APS**; enter your APS Client ID and Client Secret, save and test the connection. On Windows, the optional remembered secret uses DPAPI for the current user.
3. Open the matching SketchUp model, select a `.step` or `.stp` file in the FamilyBridge panel, enter the product code and name, and choose a destination folder.
4. Run **Gerar RFA na APS**. Two cloud WorkItems run in sequence. The RFA filename follows the saved SKP filename when available.

The SKP is a reference for metadata and naming; **RFA geometry comes from the selected STEP**. The extension attempts individual solids first and uses a mesh only for a body that cannot be converted into a Revit solid. Per-body RGB is supported when a uniform color is available. This does not transfer CAD feature history, physical materials, textures, MEP connectors or alternative family types.

Two nine-body product conversions completed both APS stages; a user opened one RFA in Revit. Exact solid/mesh counts in those successful jobs were not independently recorded, and an original STEP body's computed volume differed from the Fusion-isolated version. See [validation](docs/VALIDACAO_APS.md). The software is not certified by Autodesk or SketchUp.

Version 0.9.3 attempts `copyToComponent` before `moveToComponent` after a different STEP triggered a Fusion `cut_raw()` error. This path still needs an APS retest with the affected STEP.

For source, setup, troubleshooting and contribution details, use the [Portuguese README](README.md) and linked guides. Build the installable RBZ and source ZIP with `python3 build_release.py --output dist`.

## License

Copyright © 2026 Yruam Kaffer de Faria. Original FamilyBridge code is licensed under the **PolyForm Noncommercial License 1.0.0** ([full terms](LICENSE.txt)), matching the author's FreeCAD Bridge project. It does not give third parties unrestricted commercial use. See [third-party notices](NOTICE.md); Autodesk and SketchUp components and services keep their own terms.
