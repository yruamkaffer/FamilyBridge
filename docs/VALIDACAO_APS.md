# Validação real: dois modelos de nove corpos

Data: 23/10/2026. Versão da extensão e dos workers: 0.9.2. Requisito de abertura: Revit 2024 ou posterior.

## Evidências disponíveis

| Produto | Fusion Automation | Revit Automation 2024 | Saída | Abertura no Revit |
| --- | --- | --- | --- | --- |
| Modelo A | `success`, SAT e STEP por corpo baixados | `success` | RFA nomeado a partir do SKP | Não verificada nesta rodada |
| Modelo B | `success`, SAT e STEP por corpo baixados | `success` | RFA nomeado a partir do SKP | Usuário abriu e relatou que parece correto |

Ambos os pacotes contêm nove corpos no manifesto Fusion. Os recibos `aps-job.json` e `aps-revit-job.json` registram sucesso e download; os RFAs têm assinatura de contêiner compatível com arquivo Revit. Não havia `aps-revit-report.txt` nos pacotes, porque a v0.9.2 só baixa o relatório remoto quando um WorkItem falha. Assim, os recibos não informam quantos corpos se tornaram `FreeFormElement` nem quais tiveram fallback `DirectShape`.

## Comparação geométrica independente

O STEP original e cada STEP isolado do modelo B foram lidos com OpenCascade. Oito dos nove corpos mantiveram volume, dimensões e centro quase idênticos. Uma peça comum aos dois modelos apresentou **volume calculado divergente**, embora a área de superfície e as dimensões da caixa envolvente fossem quase iguais; a quantidade de faces também mudou. As duas representações passaram na verificação topológica. Esses dados sugerem uma diferença na interpretação das faces durante a importação/exportação, mas **não demonstram** equivalência de superfícies ou volume físico. O manifesto `colors.json` registra o volume **após** a importação no Fusion; a validação seguinte do Revit compara contra esse valor e, portanto, não detecta divergência em relação ao volume calculado no STEP original. Medidas exatas e modelos de clientes não integram este repositório.

## Estado e próxima conferência

O fluxo ponta a ponta e a abertura visual do modelo B estão confirmados. Faltam uma leitura do relatório de sucesso da APS ou uma inspeção por categoria/tipo de cada elemento no Revit para contar sólidos e malhas, e uma checagem independente da peça com o CAD que produziu o STEP. Não publique uma promessa de equivalência geométrica exata para qualquer STEP com base apenas nesses dois produtos.

Para conferir no Revit: abra a vista 3D em **Sombreado**, selecione individualmente os corpos e consulte **Propriedades**. Registre quantos são elementos de forma livre e quantos são `DirectShape`; confira RGB/material, categoria, parâmetros `FB_*`, nome e dimensões. Compare a peça divergente diretamente com o modelo CAD original se o volume for um requisito de fabricação. Guarde os relatórios e arquivos do cliente fora do repositório público.
