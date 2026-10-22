# Segurança

- Nunca publique Client Secret, tokens OAuth, arquivos de preferências SketchUp, URLs assinadas ou credenciais de uma conta APS. Use exemplos fictícios.
- A opção **Lembrar segredo** protege o Client Secret com DPAPI vinculado ao usuário atual no Windows 64 bits. Sem DPAPI, o segredo fica apenas na sessão de execução.
- `metadata.json`, `model.skp`, `model.step`, `model.sat`, `colors.json`, `output.rfa` e prévias podem revelar propriedade intelectual e dados do produto. Trate-os como privados por padrão.
- Relatórios e diagnósticos gerados pela extensão passam por sanitização, mas verifique cada arquivo antes de criar issue pública.
- Antes de um `git add`, confira `git status --short` e `git diff --cached --stat`. Se um segredo entrou em um commit, revogue-o na APS e remova-o do histórico antes da publicação.
- Para relatar uma vulnerabilidade, contate o mantenedor por canal privado indicado no perfil do repositório. Não inclua um segredo real na descrição do problema.
