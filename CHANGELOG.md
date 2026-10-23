## 0.9.2 — 23/10/2026

- Validação posterior à distribuição: dois modelos concluíram Fusion e Revit na APS, baixaram RFAs com nove corpos de origem; o usuário abriu um deles no Revit e confirmou a aparência geral. A inspeção dos STEP revelou divergência no volume calculado para a peça 8, apesar de área e dimensões quase iguais. Ver `docs/VALIDACAO_APS.md`. Esta atualização acrescenta documentação e avisos de licença ao RBZ; não altera os workers.
- O job real da v0.9.1 parou no Fusion na peça 2: volume inalterado, mas a caixa aproximada variou 1,565 mm após movê-la para a ocorrência identidade. O limite de 0,1 mm era excessivamente rígido; nenhum RFA foi produzido.
- Aceita até 5 mm de variação da caixa durante o isolamento, mantendo a conferência de volume a 0,1% e o bloqueio de alterações maiores de orientação. Registra os desvios por corpo no relatório Fusion. Corrige o texto do painel sobre pacotes válidos para reprocessamento.

## 0.9.1 — 23/10/2026

- O job real da v0.9.0 chegou ao corpo 10, mas parou com um desvio de caixa de 66,6 mm. A inspeção do STEP original e isolado confirmou que o isolamento alterou a orientação da peça, apesar do volume praticamente igual. Não foi produzido RFA.
- Fusion move cada corpo para uma ocorrência identidade na raiz, preservando as coordenadas do conjunto, e interrompe se a caixa ou o volume mudar durante o isolamento. Reutiliza o worker Revit da v0.9.0, com preferência por sólido e malha por corpo quando necessário.
- É necessária uma conversão **completa**. Reprocessar apenas o Revit com `bodies.fbdat` e `steps.fbdat` anteriores mantém os arquivos com orientação incorreta. Validação do novo fluxo na APS ainda pendente.

## 0.9.0 — 23/10/2026

- A execução real da v0.8.9 mostrou que o corpo 2 foi importado como malha de 16.624 triângulos tanto por STEP como pelo `ShapeImporter` SAT. Nenhum RFA foi salvo.
- Mantém SAT, STEP e `ShapeImporter` como tentativas de sólido. Quando um corpo não produzir sólido, reconstrói somente sua malha em um `DirectShape` com RGB e mantém `FreeFormElement` para os demais. Registra índices dos corpos em malha.
- Compara volume e dimensões da malha ao manifesto antes de incluí-la. Se a malha não passar, interrompe em vez de salvar geometria duvidosa. Compilação e testes locais não substituem a execução APS.
- Pacotes originais v0.8.8+ podem ser reprocessados só no Revit; selecionar a pasta original com recibo Fusion bem-sucedido.

## 0.8.9 — 23/10/2026

- O job real da v0.8.8 recebeu dez SATs e dez STEPs. O corpo 2 gerou zero sólidos em ambas as importações, portanto não foi criado RFA.
- A inspeção offline do STEP isolado do corpo 2 confirmou um sólido válido, com 896 faces e volume aproximado de 2652,14 mm³.
- Acrescenta diagnóstico dos tipos de geometria retornados pelo Revit e uma tentativa direta com `ShapeImporter.Convert` para o SAT. Aceita somente um `Solid` com volume positivo e mantém as verificações de dimensões, volume e cor. A tentativa não foi homologada na APS.
- O pacote v0.8.8 já contém `bodies.fbdat` e `steps.fbdat`: o teste da v0.8.9 pode reprocessar somente o Revit.

## 0.8.8 — 23/10/2026

- No job real da v0.8.7, o SAT do corpo 2 foi recebido, mas produziu zero sólidos no Revit. A inspeção offline encontrou dez sólidos válidos no STEP original; o SAT desse corpo tem 2811 faces e cerca de 21 MB.
- Fusion exporta também um STEP isolado por corpo no arquivo FBS1 `steps.fbdat`. Revit 2024 tenta importar o STEP do mesmo índice quando o SAT não gera exatamente um sólido; mantém as verificações de volume, dimensões e RGB antes de criar `FreeFormElement`.
- Reprocessamento só do Revit exige pacotes v0.8.8+ com FBB1 e FBS1. Pacotes anteriores precisam de conversão completa. Compilação e testes locais passaram; o fallback ainda depende de validação APS real.

# Histórico de alterações

## 0.8.7 — 23/10/2026

- O reprocessamento real na v0.8.6 confirmou o primeiro SAT como um sólido; o volume divergiu apenas 0,33%, mas a caixa geométrica importada mediu 175,737 × 49,191 × 139,555 mm contra 172,593 × 46 × 138,273 mm do Fusion.
- Mantém vínculo por posição no arquivo de SATs isolados, exige um sólido por entrada, volume com diferença inferior a 2% e desvio das dimensões e eixos inferior a 5 mm. Os desvios passam a ser registrados por corpo.
- Se algum corpo exceder tolerâncias, reúne os desvios geométricos no relatório do mesmo WorkItem. O RFA final ainda depende de validação APS.
- Reprocessar só o Revit continua disponível para pacotes v0.8.5+ contendo `bodies.fbdat`.

## 0.8.6 — 23/10/2026

- O WorkItem real da v0.8.5 confirmou dez SATs individuais no Revit; o primeiro corpo gerou um sólido, mas a conferência de dimensões falhou. Volume do primeiro corpo: Fusion 265430,681 mm³; Revit 264547,466 mm³ (diferença de cerca de 0,33%).
- Corrige a leitura dos limites de `Solid.GetBoundingBox`: aplica `BoundingBoxXYZ.Transform` aos cantos antes de comparar dimensões e calcular o deslocamento da geometria. Registra as medidas comparadas para investigar divergências restantes.
- Permite reprocessar **apenas o Revit** com o pacote v0.8.5 que já contém `bodies.fbdat`, sem repetir o Fusion. A criação final do RFA ainda depende de teste real.

## 0.8.5 — 23/10/2026

- Corrige falha de compilação no Fusion Automation v0.8.4: o script não reconhecia `Buffer` nem `Uint8Array.toString("ascii")`.
- Monta o arquivo FBB1 com `Uint8Array` e verifica a assinatura SAT lendo bytes explicitamente. O worker Revit permanece o mesmo da v0.8.4.
- Acrescenta teste que impede a volta dessas construções ao AppBundle Fusion distribuído.
- O WorkItem da v0.8.4 falhou antes de produzir qualquer SAT; é necessária uma conversão completa com a v0.8.5. A execução real da v0.8.5 ainda está pendente.

## 0.8.4 — 23/10/2026

- Exporta um SAT isolado para cada corpo do STEP no Fusion, preservando a ordem de `colors.json` em `bodies.fbdat` (formato FBB1); mantém `model.sat` completo para diagnóstico.
- Importa cada SAT individual no Revit, verifica quantidade, dimensões, volume e posição, cria um `FreeFormElement` e material RGB por corpo. Interrompe se não conseguir provar a correspondência.
- Reprocessamento só do Revit exige pacote gerado nesta versão ou posterior com `bodies.fbdat`; pacotes antigos exigem nova conversão completa no Fusion.
- A execução real falhou na compilação TypeScript do Fusion antes de criar os SATs; corrigido na v0.8.5.

## 0.8.3 — 23/10/2026

- Registra quantidade, dimensões e volume dos sólidos extraídos pelo Revit do SAT completo.
- Introduz reprocessamento apenas do WorkItem Revit para pacotes com SAT e manifesto RGB prontos.
- Relatório real: Fusion identificou dez corpos, mas a importação do SAT completo retornou um único sólido no Revit. Sem correspondência confiável, a criação da família foi bloqueada.

## 0.8.2 — 22/10/2026

- Corrige o AppBundle distribuído: a v0.8.1 trazia por engano um DLL antigo (`worker 0.5.0`) que exigia `model.skp`, embora a Activity atual entregasse `model.sat` e `colors.json`.
- Recompila o worker Revit 2024 a partir do fonte SAT/RGB e adiciona teste que lê o DLL efetivamente empacotado, barrando regressões com `model.skp`.
- Uma nova execução APS ainda é necessária para homologar a saída RFA e as cores.

## 0.8.1 — 22/10/2026

- Redesenha ícones, painel em três etapas e formulário de configurações APS; mostra categorias em português.
- Inclui manifesto RGB por corpo no caminho Fusion → Revit e materiais de família correspondentes.
- Faz correspondência de sólidos por dimensões e volume; interrompe casos ambíguos ou cores diferentes no mesmo corpo.
- Grava a família internamente com o nome do SKP antes de copiar para o `output.rfa` técnico da APS.
- Acrescenta documentação e alinha o template de Activity aos cinco parâmetros do cliente Ruby. O AppBundle Revit publicado nesta versão ainda continha o DLL antigo.

## 0.7.0

- Introduz o fluxo STEP → Fusion Automation → SAT → Revit Automation 2024, com dois WorkItems sequenciais e recibos.
- Produz sólidos `FreeFormElement` a partir da importação SAT.

## 0.5.2

- Nomeia o RFA pelo SKP aberto; quando não salvo, usa código e produto.

## 0.5.1

- Corrige a referência ao nome curto do AppBundle na linha de comando.
- Oculta URLs e credenciais dos relatórios e expõe estado remoto no diagnóstico.

## 0.5.0

- Migra o worker para Revit Automation 2024 e passa a produzir RFA 2024.
- Melhora diagnóstico de erros da APS e validações de engine.

## 0.4.1

- Diferencia erros HTTP e salva diagnóstico com credenciais ocultadas.

## 0.2.0 — 20/10/2026

- Adiciona cliente APS Python experimental, versionamento de AppBundle e Activity, upload, WorkItem, recibo, acompanhamento e download.
- Endurece validação de metadados, nomes, categorias e pastas de exportação.

## 0.1.0 — 20/10/2026

- Protótipo SketchUp com formulário BIM, exportação SKP 2020 e JSON.
