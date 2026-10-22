# Instalação e uso

[Início](../README.md) · [Diagnóstico](DIAGNOSTICO.md)

## Pré-requisitos

- SketchUp para desktop com Gerenciador de Extensões e conexão à internet.
- Aplicação Autodesk Platform Services (APS) com Client ID, Client Secret e acesso aos engines `Autodesk.Fusion+Latest` e `Autodesk.Revit+2024` de Design Automation.
- Um SKP correspondente ao produto e um STEP `.step`/`.stp` contendo sólidos; a extensão verifica a assinatura ISO-10303-21 e limita a entrada STEP a 100 MB, mas essa verificação não garante que haja sólidos válidos.
- Permissão para criar arquivos na pasta escolhida e franquia APS disponível. Confira disponibilidade, limites e preço vigentes na conta APS; a extensão não ativa assinatura paga.
- Para abrir o arquivo final, Revit 2024 ou posterior, ou outra ferramenta com suporte adequado a RFA 2024. **Não é preciso instalar Revit para gerar o arquivo.**

O RFA não é retrocompatível com Revit 2022. A disponibilidade de versões dos engines depende da APS; a implementação atual solicita especificamente Revit 2024.

## Instalação

1. Baixe `FamilyBridge_v0.8.1.rbz` da entrega.
2. No SketchUp: **Janela → Gerenciador de Extensões → Instalar extensão**.
3. Selecione o RBZ, aceite a instalação e abra o menu ou a barra de ferramentas **FamilyBridge**.
4. Entre em **Configurações APS**. Informe Client ID e Client Secret da sua aplicação; Owner pode ficar vazio para usar o Client ID, e o alias padrão é `dev`. Clique **Salvar** e depois **Testar conexão**.
5. Se marcar **Lembrar segredo** no Windows 64 bits, o valor é protegido com DPAPI para o usuário do Windows. Em outro ambiente, deixe desmarcado e informe o segredo em cada sessão.

O segredo digitado some visualmente do campo após salvar; o estado **segredo armazenado** no painel indica que o valor continua disponível. Ao trocar de Client ID, digite o segredo correspondente.

## Gerar uma família

1. Abra o SKP e confirme que representa o mesmo produto do STEP. Salve o SKP com o nome que deseja no arquivo RFA.
2. No painel, selecione o STEP. É ele que fornece a geometria e, quando presentes e compatíveis, as cores; a aparência do SKP não é transferida.
3. Preencha código e nome do produto, obrigatórios. Escolha uma categoria suportada: **Modelos genéricos**, **Peças hidráulicas**, **Equipamentos mecânicos** ou **Mobiliário**. Esses rótulos são enviados como identificadores internos em inglês.
4. Use **Salvar dados** se quiser apenas registrar os campos no SKP. Use **Gerar RFA na APS** para exportar o pacote e iniciar os WorkItems. Escolha a pasta de destino.
5. Aguarde Fusion e Revit terminarem. Os trabalhos são sequenciais e podem consumir franquia. Não repita o envio enquanto houver um job ativo ou antes de conferir um recibo existente.

A extensão cria uma pasta própria com `model.skp` (cópia SketchUp 2020), `model.step`, `metadata.json`, `README.txt` e, se a captura funcionar, `preview.png`. Depois acrescenta `model.sat`, `colors.json`, recibos e o RFA nomeado. Se já existir uma pasta com o mesmo código/nome, cria outra para não substituir a anterior.

## Conferir no Revit

1. Abra o RFA no Revit 2024 ou mais recente. Para avaliar materiais, use uma vista 3D com estilo visual que mostre cores/materiais, como **Sombreado** ou **Realista**. Uma vista de linhas ocultas não prova a ausência de cor.
2. Selecione cada sólido e confira se é `FreeFormElement`, se a forma é volumétrica e se há um material RGB atribuído. Compare dimensões e volume com o STEP original; as dimensões em `metadata.json` são a caixa envolvente do **SKP**, então podem diferir do STEP.
3. Abra **Tipos de família** para conferir `FB_Codigo`, `FB_Produto`, `FB_Fabricante`, `FB_Linha`, `FB_Acabamento`, `FB_Descricao` e `FB_Site`; confira também os parâmetros nativos disponíveis e a categoria em **Categoria e parâmetros da família**.
4. Confira nome interno e nome do RFA. Se o SKP estava salvo, ambos devem refletir seu nome.

Se o modelo tiver cores por face no mesmo corpo, texturas ou acabamento metálico sofisticado, a aparência pode divergir. Consulte [Dados e parâmetros](DADOS_E_PARAMETROS.md) e [Diagnóstico](DIAGNOSTICO.md).
