# Desenvolvimento, testes e publicação

[Início](../README.md) · [Arquitetura](ARQUITETURA.md) · [Contribuição](../CONTRIBUTING.md)

## Preparar o repositório GitHub

Extraia `FamilyBridge_projeto_v0.9.3.zip` e coloque o **conteúdo** da pasta `FamilyBridge_v0.9.3` na raiz de um repositório próprio do FamilyBridge; não misture com os fontes do FreeCAD Bridge. Inclua `sketchup/family_bridge/resources/FamilyBridgeAutomation2024.bundle.zip` e `FamilyBridgeStepToSat.bundle.zip`: o RBZ depende deles. `LICENSE.txt` e `NOTICE.md` também integram o RBZ em `family_bridge/resources/`. Revise o histórico de commits e a área de staging para garantir que nenhum Client Secret, token, pacote de cliente ou relatório privado seja publicado.

```sh
git init
git add .
git status --short
git commit -m "Atualiza FamilyBridge v0.9.3"
```

Crie o repositório na sua conta GitHub e configure o remoto conforme a URL exibida lá. O código original usa a licença PolyForm Noncommercial 1.0.0; veja `LICENSE.txt` e `NOTICE.md`.

## Testes locais

Requer Python 3 e Ruby com `minitest` para os testes. Rode na raiz:

```sh
python3 tests/test_bundle.py
python3 -m unittest discover -s tests -p 'test_aps_client.py'
ruby tests/test_export.rb
ruby tests/test_cloud_converter.rb
```

`test_export.rb` substitui SketchUp por objetos de teste. `test_cloud_converter.rb` simula respostas HTTP, incluindo dois WorkItems, arquivos FBB1/FBS1 e erro SAT/STEP. `test_bundle.py` compara os contratos de Activity e inspeciona os bundles. `test_aps_client.py` cobre o cliente Python legado; seu sucesso não prova o caminho Ruby de produção. Nenhum teste local valida aparência final ou abertura de RFA no Revit.

## Gerar a entrega

```sh
python3 build_release.py --output dist
```

O script produz `FamilyBridge_v0.9.3.rbz` na raiz e `dist/FamilyBridge_projeto_v0.9.3.zip`. O RBZ inclui os arquivos de `sketchup/` e as cópias da licença e do aviso; o ZIP contém documentação, fontes, testes, bundles e o próprio RBZ. O empacotador usa uma lista explícita de arquivos para evitar credenciais, saídas de jobs e caches. Confira sempre `unzip -l` ou equivalente antes de publicar.

## Alterar os workers

- **Fusion:** fonte em `aps/fusion/FamilyBridgeStepToSat/Contents/main.ts`, manifesto `PackageContents.xml`; o bundle pré-compilado fica em `sketchup/family_bridge/resources/`.
- **Revit:** fonte em `aps/revit2024/FamilyBridgeApp.cs`, manifesto `PackageContents.xml` e `package_bundle.py`. Para recompilar, é preciso uma toolchain .NET/C# compatível, referências da API Revit 2024 e `DesignAutomationBridge.dll` obtidas pelos meios permitidos pela Autodesk. O arquivo local `compile.rsp`, quando presente, é apenas um retrato de caminhos de desenvolvimento e não integra o ZIP publicado; gere referências para sua máquina. O usuário final não precisa dessa toolchain.
- A versão instalada é **2024**; editar `aps/revit2024/activity.template.json` isoladamente não muda a Activity em execução. Atualize também o construtor de Activity em `sketchup/family_bridge/cloud_converter.rb`, os testes, o AppBundle e o RBZ. Alterações nos workers podem exigir nova versão/alias na conta APS.

O cliente `aps/familybridge.py` e `aps/urls.example.json` pertencem ao protótipo antigo de uma etapa com `model.skp`. Não use esse exemplo para depurar o pipeline STEP → SAT → RFA. Para conhecer os contratos atuais, consulte [Arquitetura](ARQUITETURA.md).

## Critério de validação de uma nova versão

Execute os quatro comandos de teste, gere e examine os arquivos de distribuição e instale o RBZ no SketchUp. Dois produtos de nove corpos já concluíram a v0.9.2 na APS; um deles abriu no Revit. Veja [Validação](VALIDACAO_APS.md). Para a homologação geométrica, inspecione em Revit 2024+ a quantidade de sólidos `FreeFormElement` e de malhas `DirectShape`, materiais RGB, categoria, parâmetros, dimensões e nome interno. Documente o resultado e preserve os relatórios sem credenciais. Investigue a divergência da peça 8 diretamente no CAD de origem. Pacotes anteriores à v0.9.2 exigem novo Fusion para preservar a orientação da montagem.

## Referências primárias

- [APS Design Automation](https://aps.autodesk.com/apis-and-services/design-automation-api)
- [Documentação APS](https://aps.autodesk.com/en/docs/design-automation/v3/developers_guide/overview/)
- [SketchUp Ruby API](https://ruby.sketchup.com/)
- [Revit API Developer Guide](https://www.autodesk.com/developer-network/platform-technologies/revit)


## Build do worker Revit 2024 (v0.9.4)

Envie o conteúdo do projeto para o GitHub e execute **Actions → Build FamilyBridge 2024 → Run workflow**. O runner Windows restaura as referências .NET Framework e Revit 2024 para compilação, extrai o DesignAutomationBridge.dll já licenciado do AppBundle existente, compila `aps/revit2024/FamilyBridge.Automation.csproj`, substitui o DLL no AppBundle e cria um artifact com o RBZ instalável e o ZIP do projeto. A referência RevitAPI.dll é só de build e não vai para o RBZ.

**Não instale nem publique o AppBundle presente no ZIP de código-fonte antes do workflow:** ele é o binário anterior. Instale apenas `FamilyBridge_v0.9.4.rbz` obtido no artifact após um workflow concluído com sucesso. Confirme a linha `worker 0.9.4 solid-first STEP retry RGB` no relatório do próximo job APS. Para a peça 2 do modelo de 15 corpos, confira se o relatório registra a tentativa STEP e um sólido aprovado ou uma malha individual validada; sem isso, o RFA continua pendente.
