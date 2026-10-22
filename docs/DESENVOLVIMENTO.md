# Desenvolvimento, testes e publicação

[Início](../README.md) · [Arquitetura](ARQUITETURA.md) · [Contribuição](../CONTRIBUTING.md)

## Preparar o repositório GitHub

Extraia `FamilyBridge_projeto_v0.8.1.zip` e coloque o **conteúdo** da pasta `FamilyBridge_v0.8.1` na raiz do repositório. Inclua `sketchup/family_bridge/resources/FamilyBridgeAutomation2024.bundle.zip` e `FamilyBridgeStepToSat.bundle.zip`: o RBZ depende deles. Revise o histórico de commits e a área de staging para garantir que nenhum Client Secret, token, pacote de cliente ou relatório privado seja publicado.

```sh
git init
git add .
git status --short
git commit -m "Adiciona FamilyBridge v0.8.1"
```

Crie o repositório na sua conta GitHub e configure o remoto conforme a URL exibida lá. Este projeto não escolhe licença automaticamente; veja `NOTICE.md`.

## Testes locais

Requer Python 3 e Ruby com `minitest` para os testes. Rode na raiz:

```sh
python3 tests/test_bundle.py
python3 -m unittest discover -s tests -p 'test_aps_client.py'
ruby tests/test_export.rb
ruby tests/test_cloud_converter.rb
```

`test_export.rb` substitui SketchUp por objetos de teste. `test_cloud_converter.rb` simula respostas HTTP, incluindo dois WorkItems e erro SAT. `test_bundle.py` compara os contratos de Activity e inspeciona os bundles. `test_aps_client.py` cobre o cliente Python legado; seu sucesso não prova o caminho Ruby de produção. Nenhum teste local valida aparência final ou abertura de RFA no Revit.

## Gerar a entrega

```sh
python3 build_release.py --output dist
```

O script produz `FamilyBridge_v0.8.1.rbz` na raiz e `dist/FamilyBridge_projeto_v0.8.1.zip`. O RBZ inclui os arquivos de `sketchup/` na raiz do arquivo instalável; o ZIP contém documentação, fontes, testes, bundles e o próprio RBZ. O empacotador usa uma lista explícita de arquivos para evitar credenciais, saídas de jobs e caches. Confira sempre `unzip -l` ou equivalente antes de publicar.

## Alterar os workers

- **Fusion:** fonte em `aps/fusion/FamilyBridgeStepToSat/Contents/main.ts`, manifesto `PackageContents.xml`; o bundle pré-compilado fica em `sketchup/family_bridge/resources/`.
- **Revit:** fonte em `aps/revit2024/FamilyBridgeApp.cs`, manifesto `PackageContents.xml` e `package_bundle.py`. Para recompilar, é preciso uma toolchain .NET/C# compatível, referências da API Revit 2024 e `DesignAutomationBridge.dll` obtidas pelos meios permitidos pela Autodesk. O arquivo local `compile.rsp`, quando presente, é apenas um retrato de caminhos de desenvolvimento e não integra o ZIP publicado; gere referências para sua máquina. O usuário final não precisa dessa toolchain.
- A versão instalada é **2024**; editar `aps/revit2024/activity.template.json` isoladamente não muda a Activity em execução. Atualize também o construtor de Activity em `sketchup/family_bridge/cloud_converter.rb`, os testes, o AppBundle e o RBZ. Alterações nos workers podem exigir nova versão/alias na conta APS.

O cliente `aps/familybridge.py` e `aps/urls.example.json` pertencem ao protótipo antigo de uma etapa com `model.skp`. Não use esse exemplo para depurar o pipeline STEP → SAT → RFA. Para conhecer os contratos atuais, consulte [Arquitetura](ARQUITETURA.md).

## Critério de validação de uma nova versão

Execute os quatro comandos de teste, gere e examine os arquivos de distribuição e instale o RBZ no SketchUp. Em uma conta APS de teste, envie um STEP sólido com dois corpos de cores distinguíveis, veja ambos os WorkItems e inspecione no Revit 2024+: sólidos, materiais RGB, categoria, parâmetros, dimensões e nome interno. Documente o resultado e preserve os relatórios sem credenciais. Até essa execução, descreva suporte RGB como não homologado.

## Referências primárias

- [APS Design Automation](https://aps.autodesk.com/apis-and-services/design-automation-api)
- [Documentação APS](https://aps.autodesk.com/en/docs/design-automation/v3/developers_guide/overview/)
- [SketchUp Ruby API](https://ruby.sketchup.com/)
- [Revit API Developer Guide](https://www.autodesk.com/developer-network/platform-technologies/revit)
