# Como contribuir

Autoria principal e titular do copyright original: **Yruam Kaffer de Faria**. Respeite a [PolyForm Noncommercial License 1.0.0](LICENSE.txt). Contribuir não transfere automaticamente a titularidade do código de seu autor. Caso pretenda conceder uso comercial de sua contribuição, trate os direitos separadamente com o mantenedor.

Antes de abrir uma proposta, consulte [README.md](README.md), [Arquitetura](docs/ARQUITETURA.md) e [Desenvolvimento](docs/DESENVOLVIMENTO.md). Descreva o comportamento observado, a versão do SketchUp, o estágio APS e passos de reprodução sem credenciais. Mudanças na Activity, nos manifestos ou nos parâmetros exigem atualizar cliente Ruby, worker, template de referência, testes e bundle distribuído.

Execute os testes locais descritos em `docs/DESENVOLVIMENTO.md` e indique claramente se houve teste APS/Revit real. Não anexe produtos proprietários, tokens ou URLs assinadas em issues e pull requests. Inclua no PR o problema, a mudança, testes realizados e limites conhecidos; alterações de geometria precisam de amostras autorizadas e evidência de medidas/posição.

Antes de publicar, revise `git status --short`, `git diff --cached --stat`, o ZIP do projeto e o RBZ. As pastas produzidas por conversões APS e os RFAs de clientes não integram o repositório.
