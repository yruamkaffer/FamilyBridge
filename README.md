# FamilyBridge

Extensão para SketchUp que transforma um **STEP sólido** em uma família **RFA 2024** pela Autodesk Platform Services (APS). O painel coleta informações BIM, guarda os dados no modelo SketchUp e coordena dois trabalhos em nuvem: Fusion Automation converte STEP em SAT e extrai cores RGB por corpo; Revit Automation 2024 cria sólidos `FreeFormElement`, materiais e parâmetros de família.

**Versão:** 0.8.1 · **Autor:** Yruam Käffer de Faria · **Idioma da interface:** português.

> **Estado de validação:** exportação do pacote, fluxo de rede simulado, estrutura dos AppBundles e compilação do worker Revit 2024 foram verificados. A atualização de cores por corpo desta versão **ainda não foi validada por WorkItems reais na APS**. Confira o resultado no Revit antes de distribuir famílias produzidas por ela.

## Comece aqui

1. Tenha SketchUp com suporte a extensões Ruby e acesso à sua aplicação APS com Design Automation habilitada para `Autodesk.Fusion+Latest` e `Autodesk.Revit+2024`. Consulte limites e cobrança atuais no portal APS antes de enviar trabalhos.
2. No SketchUp, abra **Janela → Gerenciador de Extensões → Instalar extensão** e selecione `FamilyBridge_v0.8.1.rbz`.
3. Abra **FamilyBridge → Configurações APS**, informe Client ID e Client Secret, salve e teste a conexão. A opção **Lembrar segredo** usa DPAPI no Windows; em outros sistemas, use o segredo somente na sessão.
4. Abra o SKP correspondente ao produto. No painel FamilyBridge, escolha um arquivo `.step` ou `.stp` sólido, preencha **código**, **nome** e, se desejar, fabricante, linha, acabamento, descrição, site e categoria.
5. Clique **Gerar RFA na APS** e escolha a pasta de destino. Aguarde a conclusão dos dois trabalhos. O arquivo final recebe o nome do SKP salvo; se o modelo não tiver nome salvo, usa código e produto.

O `model.skp` exportado é uma referência; **a geometria do RFA vem do STEP selecionado**. A extensão não requer Revit, Fusion ou FreeCAD instalados localmente. O STEP pode ser exportado pelo FreeCAD ou por outro CAD compatível.

[Instalação e uso detalhado](docs/INSTALACAO_E_USO.md) · [Arquitetura](docs/ARQUITETURA.md) · [Dados e parâmetros](docs/DADOS_E_PARAMETROS.md) · [Diagnóstico](docs/DIAGNOSTICO.md) · [Desenvolvimento](docs/DESENVOLVIMENTO.md)

## O que a família contém

| Recurso | Resultado |
| --- | --- |
| Geometria | Sólidos importados do SAT recriados como `FreeFormElement`, sem histórico paramétrico CAD |
| Cores | Materiais com RGB por corpo, quando o STEP/Fusion expõe uma cor uniforme por corpo |
| Metadados | Parâmetros `FB_*` de texto e parâmetros nativos de identidade quando disponíveis |
| Categoria | Modelos genéricos, peças hidráulicas, equipamentos mecânicos ou mobiliário |
| Versão RFA | Revit **2024 ou posterior**; não abre no Revit 2022 |
| Nome | Nome do arquivo SKP salvo; `output.rfa` é apenas o nome técnico da saída do WorkItem |

O fluxo não cria conectores MEP, cotas paramétricas, tipos de família alternativos ou materiais com textura/brilho. Cores diferentes em faces do mesmo corpo e corpos geometricamente indistinguíveis com cores diferentes provocam erro explícito.

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

Para instalar, use o **RBZ**, não o ZIP do projeto. Para publicar o código no GitHub, extraia o ZIP e envie **o conteúdo da pasta `FamilyBridge_v0.8.1`** para a raiz do repositório. Não envie pacotes gerados com dados de clientes, segredos ou relatórios de jobs.

## Desenvolvimento rápido

```sh
python3 tests/test_bundle.py
python3 -m unittest discover -s tests -p 'test_aps_client.py'
ruby tests/test_export.rb
ruby tests/test_cloud_converter.rb
python3 build_release.py --output dist
```

Os testes Ruby usam mocks de SketchUp e APS; não abrem SKP/RFA reais. Para alterar os workers, veja [Desenvolvimento](docs/DESENVOLVIMENTO.md). Consulte [CHANGELOG.md](CHANGELOG.md) para o histórico e [SECURITY.md](SECURITY.md) para cuidados com credenciais e relatórios.

## Licenciamento e serviços

Nenhuma licença de redistribuição para este código foi definida neste pacote. O autor deve escolher uma licença antes de aceitar contribuições ou autorizar reutilização externa. SketchUp, Autodesk, Revit, Fusion e APS são marcas e serviços de seus respectivos titulares; os termos e a cobrança do serviço APS são independentes deste projeto. Veja [NOTICE.md](NOTICE.md).
