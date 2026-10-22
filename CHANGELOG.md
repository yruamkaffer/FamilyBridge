# Histórico de alterações

## 0.8.1 — 22/10/2026

- Redesenha ícones, painel em três etapas e formulário de configurações APS; mostra categorias em português.
- Inclui manifesto RGB por corpo no caminho Fusion → Revit e materiais de família correspondentes.
- Faz correspondência de sólidos por dimensões e volume; interrompe casos ambíguos ou cores diferentes no mesmo corpo.
- Grava a família internamente com o nome do SKP antes de copiar para o `output.rfa` técnico da APS.
- Acrescenta documentação e alinha o template de Activity aos cinco parâmetros do cliente Ruby. A etapa RGB aguarda validação real na APS.

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
