# TASK-056 - Normalizar comando de testes automatizados

## Contexto

O PS Panel ja possui testes implementados com o modulo nativo `node:test` em
`test/*.test.js`, mas o script `npm test` ainda e um placeholder que sempre
termina com erro. Isso impede que desenvolvedores e scripts de release usem um
unico comando confiavel para validar o projeto.

## Objetivo

Transformar `npm test` no ponto de entrada oficial da suite automatizada atual,
sem introduzir um novo framework de testes e sem alterar comportamento da
aplicacao.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

1. Alterar o script `test` do `package.json` para executar `node --test`.
2. Confirmar que todos os arquivos atuais em `test/` sao descobertos pelo
   test runner no Windows.
3. Corrigir somente problemas de descoberta ou isolamento diretamente
   necessarios para que a suite atual seja executada por um unico comando.
4. Documentar em `README.md` e `docs/patterns.md` que `npm test` passou a ser
   uma validacao real.
5. Atualizar `src/config/release.js` ao concluir a implementacao.

## Arquivos previstos

```text
package.json
README.md
docs/patterns.md
src/config/release.js
```

Alterar testes existentes somente se houver dependencia de ordem, vazamento de
estado ou outra falha real de execucao conjunta. Nao atualizar dependencias nem
o `package-lock.json`.

## Fora de escopo

- Criar novos casos de teste.
- Adicionar Jest, Mocha, Vitest ou ferramenta de cobertura.
- Executar testes contra LDAP, SMTP, Fortigate ou outros servicos reais.
- Alterar codigo funcional apenas para aumentar cobertura.
- Criar scripts PowerShell de validacao de release.

## Validacao obrigatoria

```powershell
npm test
node --test
node --check app.js
```

Os dois primeiros comandos devem executar a mesma suite e terminar com codigo
zero. Nenhum teste pode depender de `.env` real, banco SQLite de producao,
porta `3000` ou conectividade externa.

## Criterios de aceite

- `npm test` executa a suite `node:test` existente.
- Todos os testes atuais sao descobertos no Windows.
- O comando retorna codigo diferente de zero quando um teste falha.
- A documentacao deixa de afirmar que `npm test` e apenas um placeholder.
- Nenhuma dependencia ou dado local e alterado.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

Nenhuma. Esta e a primeira task da sequencia de automatizacao de release.

---

## Assinatura da LLM

- Data: 2026-08-18 11:23:31 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

Status: implementada em 2026-08-18.

- `npm test` passou a executar o test runner nativo com `node --test`.
- Os 25 testes automatizados atuais sao descobertos e executados tanto por
  `npm test` quanto por `node --test`.
- O utilitario integrado LDAP foi renomeado de
  `scripts-js/test-ldap.js` para `scripts-js/check-ldap.js`, pois o nome
  anterior era interpretado automaticamente como teste e exigia credenciais
  `TEST_USERNAME` e `TEST_PASSWORD`.
- A logica do utilitario LDAP foi preservada e nenhuma conexao LDAP foi feita
  durante a validacao.
- `README.md`, `docs/patterns.md` e a observacao correspondente em
  `docs/architecture.md` foram atualizados.
- O release foi incrementado para `v2026.08.18-057`.

Validacoes executadas:

- `npm test`: 25 aprovados, 0 falhas;
- `node --test`: 25 aprovados, 0 falhas;
- `node --check app.js`;
- `node --check scripts-js\check-ldap.js`.

Nenhuma dependencia, lockfile, banco SQLite ou configuracao de ambiente foi
alterada.

---

## Assinatura da LLM

- Data: 2026-08-18 11:33:19 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
