# FamilyBridge

Extensão para SketchUp que transforma um **STEP sólido** em uma família **RFA 2024** pela Autodesk Platform Services (APS). O painel coleta informações BIM, guarda os dados no modelo SketchUp e coordena dois trabalhos em nuvem: Fusion Automation exporta SAT e STEP isolados com RGB por corpo; Revit Automation 2024 tenta importar cada corpo como sólido, com fallback de malha apenas para o corpo que não produzir um sólido, e cria materiais e parâmetros de família.

**Versão:** 0.9.4 · **Autor:** Yruam Kaffer de Faria · **Idioma da interface:** português.

[English](README.en.md) · [Instalação](docs/INSTALACAO_E_USO.md) · [Diagnóstico](docs/DIAGNOSTICO.md) · [Arquitetura](docs/ARQUITETURA.md) · [Licença](LICENSE.txt)

> **Estado de validação:** a v0.9.2 concluiu os dois WorkItems APS para dois modelos reais com nove corpos cada. Um RFA foi aberto no Revit e conferido visualmente pelo usuário. A inspeção independente encontrou uma divergência de volume calculado em uma peça comum aos dois modelos; consulte [Validação](docs/VALIDACAO_APS.md). A aparência no Revit não comprova sozinha a quantidade de sólidos nem a equivalência exata de todas as superfícies.

> **Histórico 0.9.3:** um STEP adicional parou no Fusion ao mover um corpo (`cut_raw()`). Esta versão tenta copiar antes de mover e registra o índice da peça. A correção ainda não foi executada na APS com esse STEP; veja [Diagnóstico](docs/DIAGNOSTICO.md).

> **Atualização 0.9.4:** o worker tenta STEP quando o sólido SAT reprova a validação. O pacote instalável v0.9.4 só é produzido após a compilação Windows; confira o resultado do workflow antes de instalar. A execução APS de 15 corpos ainda precisa ser repetida.

## Comece aqui

1. Tenha SketchUp com suporte a extensões Ruby e acesso à sua aplicação APS com Design Automation habilitada para `Autodesk.Fusion+Latest` e `Autodesk.Revit+2024`. Consulte limites e cobrança atuais no portal APS antes de enviar trabalhos.
2. No SketchUp, abra **Janela → Gerenciador de Extensões → Instalar extensão** e selecione `FamilyBridge_v0.9.4.rbz`.
3. Abra **FamilyBridge → Configurações APS**, informe Client ID e Client Secret, salve e teste a conexão. A opção **Lembrar segredo** usa DPAPI no Windows; em outros sistemas, use o segredo somente na sessão.
4. Abra o SKP correspondente ao produto. No painel FamilyBridge, escolha um arquivo `.step` ou `.stp` sólido, preencha **código**, **nome** e, se desejar, fabricante, linha, acabamento, descrição, site e categoria.
5. Clique **Gerar RFA na APS** e escolha a pasta de destino. Aguarde a conclusão dos dois trabalhos. O arquivo final recebe o nome do SKP salvo; se o modelo não tiver nome salvo, usa código e produto.

Se o Fusion terminou e **apenas o Revit falhou por outro motivo**, use **Reprocessar só o Revit** com um pacote v0.9.2 que contenha `bodies.fbdat` e `steps.fbdat`. Pacotes anteriores à v0.9.2 precisam de **nova conversão completa** para corrigir a orientação das peças. Cada WorkItem consome franquia APS.

O `model.skp` exportado é uma referência; **a geometria do RFA vem do STEP selecionado**. A extensão não requer Revit, Fusion ou FreeCAD instalados localmente. O STEP pode ser exportado pelo FreeCAD ou por outro CAD compatível.

[Instalação e uso detalhado](docs/INSTALACAO_E_USO.md) · [Arquitetura](docs/ARQUITETURA.md) · [Dados e parâmetros](docs/DADOS_E_PARAMETROS.md) · [Diagnóstico](docs/DIAGNOSTICO.md) · [Desenvolvimento](docs/DESENVOLVIMENTO.md)

## O que a família contém

| Recurso | Resultado |
| --- | --- |
| Geometria | Sólidos por corpo como `FreeFormElement` após SAT, STEP ou `ShapeImporter`; quando só houver malha, `DirectShape` com material RGB nesse corpo, sem histórico CAD |
| Cores | Materiais com RGB por corpo, quando o STEP/Fusion expõe uma cor uniforme por corpo |
| Metadados | Parâmetros `FB_*` de texto e parâmetros nativos de identidade quando disponíveis |
| Categoria | Modelos genéricos, peças hidráulicas, equipamentos mecânicos ou mobiliário |
| Versão RFA | Revit **2024 ou posterior**; não abre no Revit 2022 |
| Nome | Nome do arquivo SKP salvo; `output.rfa` é apenas o nome técnico da saída do WorkItem |

O fluxo não cria conectores MEP, cotas paramétricas, tipos de família alternativos ou materiais com textura/brilho. Cores diferentes em faces do mesmo corpo provocam erro explícito; posição, dimensões e volume de cada corpo são conferidos antes de atribuir material. O relatório remoto da APS lista quantos corpos viraram sólidos e quais precisaram de malha; a extensão salva automaticamente esse relatório localmente quando o job falha, mas nesta versão não o baixa em caso de sucesso.

## Estrutura do repositório

| Caminho | Uso |
| --- | --- |
| `sketchup/` | Entrada da extensão, painel, configurações, cliente APS e recursos |
| `sketchup/family_bridge/resources/*.bundle.zip` | Workers pré-compilados distribuídos com o RBZ; **devem ficar no repositório** |
| `aps/fusion/` | Fonte TypeScript e manifesto do worker STEP → SAT + RGB |
| `aps/revit2024/` | Fonte C#, Activity de referência e ferramentas de empacotamento do worker |
| `aps/familybridge.py`, `aps/urls.example.json` | Cliente Python **legado**, para experimentação; não é o fluxo atual de dois WorkItems |
| `tests/` | Testes locais com simulações e inspeção de pacotes |
| `docs/` | Guias técnicos e operacionais |
| `build_release.py` | Recria o RBZ e o ZIP de projeto |

Para instalar, use o **RBZ**, não o ZIP do projeto. Para publicar o código no GitHub, crie um repositório específico para FamilyBridge, extraia o ZIP e envie **o conteúdo da pasta `FamilyBridge_v0.9.4`** para a raiz. Preserve `LICENSE.txt`, `NOTICE.md`, os AppBundles e o RBZ. Não envie STEP/SKP/RFA de clientes, pacotes de conversão, segredos ou relatórios de jobs. Consulte [Desenvolvimento](docs/DESENVOLVIMENTO.md) para os comandos sugeridos.

## Desenvolvimento rápido

```sh
python3 tests/test_bundle.py
python3 -m unittest discover -s tests -p 'test_aps_client.py'
ruby tests/test_export.rb
ruby tests/test_cloud_converter.rb
python3 build_release.py --output dist
```

Os testes Ruby usam mocks de SketchUp e APS; não abrem SKP/RFA reais. Para alterar os workers, veja [Desenvolvimento](docs/DESENVOLVIMENTO.md). Consulte [CHANGELOG.md](CHANGELOG.md) para o histórico e [SECURITY.md](SECURITY.md) para cuidados com credenciais e relatórios.

## Licença e serviços

Copyright © 2026 **Yruam Kaffer de Faria**. O código original do FamilyBridge é oferecido sob a **PolyForm Noncommercial License 1.0.0**, como no projeto [FreeCAD Bridge](https://github.com/yruamkaffer/freecad-bridge). Publicação no GitHub não autoriza uso comercial por terceiros. O titular pode conceder permissões adicionais separadamente; veja [LICENSE.txt](LICENSE.txt) e [NOTICE.md](NOTICE.md). Componentes de terceiros incorporados ou acessados continuam sujeitos aos seus próprios termos. A execução na APS depende da conta e da franquia do usuário; o plano Free não é uma promessa de uso ilimitado.
