# Diagnóstico e recuperação

[Início](../README.md) · [Arquitetura](ARQUITETURA.md)

## Falha `InternalValidationError : cut_raw()` no Fusion

Um STEP real fez a v0.9.2 falhar ao executar `moveToComponent` no worker Fusion. O aviso `colors.json` ausente é consequência dessa interrupção, não um erro de configuração do formulário. A v0.9.3 tenta `copyToComponent` primeiro, mantendo a posição do conjunto e as verificações de volume e dimensões; só recorre ao movimento se a cópia falhar. O relatório agora indica o índice do corpo antes da tentativa. **A correção precisa ser testada na APS com o STEP afetado.** Instale o RBZ novo e execute uma conversão completa em uma pasta nova; o pacote com `aps-job.json` falho não contém os sólidos isolados necessários para reprocessar somente o Revit.

## Primeiros passos

1. Registre a mensagem exibida no painel e localize a pasta do pacote. Não clique novamente para gerar na mesma pasta enquanto houver recibos.
2. Verifique `aps-job.json` (Fusion) e `aps-revit-job.json` (Revit). Eles contêm o ID/estado que ajuda a conferir o WorkItem no portal ou na API APS.
3. Consulte `aps-diagnostic.json` e, se existirem, `aps-fusion-report.txt` e `aps-revit-report.txt`. A extensão tenta ocultar credenciais e URLs assinadas, mas revise o conteúdo antes de compartilhar.
4. Para reproduzir com segurança, use **uma nova pasta** depois de confirmar o estado remoto e o consumo de franquia. Não apague recibos para forçar reenvio sem essa verificação.

| Sintoma | Onde olhar | Próxima ação |
| --- | --- | --- |
| Salvar/testar diz que faltam credenciais | Configurações APS | Informe Client ID e Client Secret da mesma aplicação. Depois de salvar, o campo do segredo pode ficar vazio visualmente; confira o indicador de armazenamento. |
| HTTP 401 | `aps-diagnostic.json` | Confira ID, segredo, aplicação e permissões. |
| HTTP 403 | Diagnóstico e portal APS | Confira acesso às APIs, engines e franquia disponível. A extensão não altera seu plano. |
| HTTP 404 / engine ausente | Diagnóstico e configuração da aplicação | Confira `Autodesk.Fusion+Latest`, `Autodesk.Revit+2024`, owner e alias. |
| HTTP 429 | Diagnóstico | Aguarde o limite de requisições e verifique se há job remoto antes de reenviar. |
| STEP inválido ou sem sólidos | `model.step` e relatório Fusion | Exporte corpos sólidos em STEP ISO-10303-21. Malhas ou superfícies isoladas podem falhar. |
| Worker `0.5.0` pede `model.skp` | `aps-revit-report.txt` | O AppBundle Revit da v0.8.1 estava desatualizado. Instale o RBZ v0.9.2 e gere um pacote novo; confira a versão do worker no novo relatório. |
| Fusion v0.8.4 cita `Cannot find name 'Buffer'` | `aps-fusion-report.txt` | A compilação parou antes da conversão. Instale a v0.9.2 e inicie uma conversão completa em nova pasta; o pacote com falha não tem SATs prontos. |
| Contagem de sólidos difere dos corpos do Fusion | `aps-revit-report.txt` | A v0.8.3 comprovou dez corpos no Fusion e um sólido importado no Revit. Use a v0.9.2 para uma **nova conversão completa** que produza `bodies.fbdat`; o pacote anterior não serve para reprocessar apenas o Revit. |
| Geometria do corpo 1 difere do manifesto (v0.8.5) | `aps-revit-report.txt` | Instale a v0.9.2 e execute uma **conversão completa**; o pacote v0.8.5 não contém `steps.fbdat`; o worker corrige a transformação da caixa geométrica e registra dimensões comparadas. |
| Geometria do corpo 1 difere do manifesto (v0.8.6) | `aps-revit-report.txt` | A caixa do Revit diferiu até 3,19 mm, com volume 0,33% diferente. Instale a v0.9.2 e execute uma **conversão completa** para obter `steps.fbdat`. O worker mantém a checagem de volume e aceita até 5 mm de desvio da caixa. |
| SAT individual incompatível | `aps-fusion-report.txt` e mensagem | Algum SAT isolado passou da versão ACIS aceita; o segundo WorkItem não é enviado. |
| Corpo 2: SAT=0 e STEP=0 (v0.8.8) | `aps-revit-report.txt` | O STEP isolado é um sólido válido em OpenCascade, mas ambas as importações no Revit retornaram zero sólidos. A v0.8.9 também retornou `Mesh` (16.624 triângulos). A v0.9.2 permite malha só nesse corpo e mantém as demais tentativas de sólido; inicie conversão completa para preservar as coordenadas de montagem. |
| Cor por face ou divergência geométrica | `colors.json`, `aps-revit-report.txt` | Examine várias cores por face, contagem, volume, dimensões e posição do SAT isolado. |
| RFA sem cor aparente | Vista 3D e materiais no Revit | Use Sombreado/Realista, selecione um sólido, confira material e RGB. Uma vista em linhas não mostra aparência. |
| Parâmetros não encontrados | Tipos de família no Revit | Procure `FB_*` na família; inspecione `metadata.json` para os valores enviados. |
| RFA não abre em 2022 | Versão do Revit | Use Revit 2024 ou posterior. Não há exportação retrocompatível para 2022. |
| Recibo existente bloqueia envio | `aps-job.json` / `aps-revit-job.json` | Confira o job anterior. Gere um novo pacote em outra pasta se decidir executar novamente. |

## Arquivos úteis para solicitar ajuda

Compartilhe versão da extensão, mensagem de erro, estágio, `aps-diagnostic.json` e o relatório do estágio. Inclua `metadata.json` e `colors.json` só depois de remover dados de produto confidenciais. Não envie Client Secret, token, arquivos de preferências, URLs assinadas, STEP/SKP/RFA proprietários sem intenção explícita.

Os testes locais verificam lógica e contratos, não comprovam o resultado geométrico ou visual de um job real. Dois produtos concluíram a v0.9.2 na APS, e o usuário abriu um deles no Revit. O número de sólidos e malhas do RFA não está confirmado sem o relatório remoto do job bem-sucedido ou inspeção de cada corpo. A peça 8 apresenta divergência de volume calculado entre o STEP original e o isolado. Consulte [Validação](VALIDACAO_APS.md).


| Corpo 10: malha fora da tolerância (v0.9.0) | `aps-revit-report.txt` | A exportação isolada mudou a orientação do corpo 10 e invalidou a caixa de comparação. Execute conversão completa com a v0.9.2; reprocessar só o Revit reutilizaria geometria isolada incorreta. |
