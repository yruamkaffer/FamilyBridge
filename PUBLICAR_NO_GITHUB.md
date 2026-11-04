# Publicar a v0.9.5

1. Extraia este ZIP e envie **o conteúdo da pasta FamilyBridge_v0.9.5** para a raiz de `yruamkaffer/FamilyBridge`, substituindo os arquivos de mesmo nome.
2. Confira especialmente `aps/revit2024/FamilyBridgeApp.cs`, `build_release.py`, `tests/test_bundle.py` e `.github/workflows/build-revit-worker.yml`. A pasta `.github` precisa permanecer na raiz do repositório.
3. O commit em `aps/revit2024/` inicia o workflow **Build FamilyBridge 2024**. Baixe o artifact **FamilyBridge-v0.9.5** somente quando a execução terminar verde.
4. Dentro do artifact, instale `FamilyBridge_v0.9.5.rbz` no SketchUp. Reprocesse só o Revit com a pasta original do pacote de 15 corpos e confira o relatório. A compilação não substitui essa validação na APS.

**Importante:** o AppBundle Revit incluído neste ZIP de código-fonte é da compilação anterior e serve para extrair a ponte Autodesk no runner. O workflow o recompila e o substitui antes de montar o RBZ v0.9.5. Não distribua um RBZ montado diretamente deste ZIP antes do workflow.
