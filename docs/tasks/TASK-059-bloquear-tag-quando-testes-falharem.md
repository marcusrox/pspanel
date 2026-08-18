# TASK-059 - Bloquear criacao de tag quando testes falharem

## Contexto

`deploy/windows/New-PSPanelReleaseTag.ps1` valida o estado do Git, a versao em
`src/config/release.js` e a sincronizacao com `origin/main`, mas ainda nao usa a
suite automatizada como pre-condicao para publicar a tag.

## Objetivo

Integrar o validador da TASK-058 ao criador de tags para garantir que nenhuma
tag de release seja criada ou enviada ao `origin` quando os testes ou as
validacoes de sintaxe falharem.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Fluxo esperado

1. Validar parametros e raiz do projeto.
2. Confirmar arvore de trabalho limpa.
3. Confirmar que `HEAD` corresponde a `origin/main`.
4. Ler e validar a versao de `src/config/release.js`.
5. Confirmar que nao existe release igual ou posterior.
6. Executar `Test-PSPanelRelease.ps1`.
7. Somente depois do sucesso criar a tag anotada.
8. Publicar a tag no remote configurado.

O `-WhatIf` deve informar que os testes fazem parte do plano, mas nao deve
criar tag nem modificar o remote. A implementacao deve decidir e documentar se
o `-WhatIf` executa os testes ou apenas valida que o script existe; a opcao
preferida e executar as validacoes para que a simulacao seja util.

## Seguranca e operacao

- Nao adicionar `-SkipTests` nesta primeira versao.
- Nao apagar automaticamente uma tag remota.
- Se o teste falhar, nenhuma operacao `git tag` ou `git push` pode ocorrer.
- Se a tag local for criada e o push falhar, preservar o diagnostico atual e
  orientar a recuperacao sem ocultar o estado parcial.
- Nao imprimir URLs com credenciais nem configuracoes sensiveis do Git.

## Arquivos previstos

```text
deploy/windows/New-PSPanelReleaseTag.ps1
README.md
INSTALL.md
src/config/release.js
```

## Fora de escopo

- Alterar o formato `vAAAA.MM.DD-NNN`.
- Fazer deploy em DEV ou producao.
- Configurar PowerShell Remoting.
- Criar GitHub Actions.
- Atualizar dependencias ou ampliar a suite de testes.

## Validacao obrigatoria

- Validar sintaxe PowerShell do script alterado.
- Executar `-WhatIf` em arvore limpa e sincronizada.
- Simular falha do validador e confirmar que nenhum comando de tag/push ocorre.
- Confirmar que uma execucao aprovada continua criando tag anotada com a
  mensagem e o commit corretos, usando remote de teste ou mocks seguros.
- Nao criar tag real no repositorio oficial durante testes automatizados.

## Criterios de aceite

- A suite completa e executada antes de qualquer criacao de tag.
- Falha de teste bloqueia tag local e remota.
- O comportamento de validacao Git existente e preservado.
- `-WhatIf` permanece sem efeitos colaterais Git.
- Mensagens operacionais permanecem em portugues.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

- TASK-058 concluida.

---

## Assinatura da LLM

- Data: 2026-08-18 11:23:31 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

Status: implementada em 2026-08-18.

`New-PSPanelReleaseTag.ps1` passou a executar obrigatoriamente
`Test-PSPanelRelease.ps1` depois das validacoes de Git e antes de qualquer
`git tag` ou `git push`. O validador roda em um processo PowerShell filho para
que seu codigo de saida seja tratado sem encerrar o criador de tags.

O parametro `RequiredNodeVersion` foi exposto no criador de tags e e repassado
ao validador. Nao foi adicionada opcao para ignorar testes. O `-WhatIf` executa
`npm ci`, `npm test` e as validacoes de sintaxe, mas continua sem criar tag local
ou remota.

Validacoes executadas em repositorio e remote temporarios:

- parser PowerShell do script alterado: sem erros;
- falha controlada de `npm test` com codigo 23: a tag candidata permaneceu
  ausente local e remotamente;
- `-WhatIf` aprovado: 47 testes, 66 arquivos JavaScript e 19 scripts PowerShell
  validados, sem criacao de tag;
- fluxo efetivo aprovado: tag anotada criada no commit esperado, com mensagem
  `Release v2026.08.18-059`, e publicada somente no remote temporario;
- `git diff --check`.

Nenhuma tag foi criada ou publicada no repositorio oficial. O release foi
atualizado para `v2026.08.18-060`.

---

## Assinatura da LLM

- Data: 2026-08-18 14:02:40 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
