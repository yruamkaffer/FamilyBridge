# Diagnóstico e recuperação

[Início](../README.md) · [Arquitetura](ARQUITETURA.md)

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
| SAT incompatível | `aps-fusion-report.txt` e mensagem | A saída SAT passou da versão ACIS aceita; o segundo WorkItem não é enviado. |
| Cores ambíguas ou contagens diferentes | `colors.json`, `aps-revit-report.txt` | Examine corpos coincidentes com cores distintas, várias cores por face e diferenças de geometria entre conversões. |
| RFA sem cor aparente | Vista 3D e materiais no Revit | Use Sombreado/Realista, selecione um sólido, confira material e RGB. Uma vista em linhas não mostra aparência. |
| Parâmetros não encontrados | Tipos de família no Revit | Procure `FB_*` na família; inspecione `metadata.json` para os valores enviados. |
| RFA não abre em 2022 | Versão do Revit | Use Revit 2024 ou posterior. Não há exportação retrocompatível para 2022. |
| Recibo existente bloqueia envio | `aps-job.json` / `aps-revit-job.json` | Confira o job anterior. Gere um novo pacote em outra pasta se decidir executar novamente. |

## Arquivos úteis para solicitar ajuda

Compartilhe versão da extensão, mensagem de erro, estágio, `aps-diagnostic.json` e o relatório do estágio. Inclua `metadata.json` e `colors.json` só depois de remover dados de produto confidenciais. Não envie Client Secret, token, arquivos de preferências, URLs assinadas, STEP/SKP/RFA proprietários sem intenção explícita.

Os testes locais verificam lógica e contratos, não comprovam o resultado geométrico ou visual de um job real. A etapa RGB da v0.8.1 ainda requer validação em execução APS real.
