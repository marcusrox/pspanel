# TASK-058 - Criar validador de release em PowerShell

## Contexto

O processo de release precisa executar, de forma reproduzivel, os testes Node e
as validacoes de sintaxe antes que uma tag possa ser criada. Hoje parte dessas
validacoes existe apenas no atualizador de producao ou em comandos manuais.

## Objetivo

Criar `deploy/windows/Test-PSPanelRelease.ps1` como comando unico e somente de
leitura para validar uma candidata a release na estacao DEV.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Comportamento esperado

O script deve:

1. resolver e validar a raiz do projeto;
2. confirmar a presenca de `app.js`, `package.json`, `package-lock.json` e dos
   diretorios esperados;
3. localizar `node.exe`, `npm.cmd` e Git;
4. validar a versao homologada do Node.js, com parametro para a versao esperada;
5. executar `npm ci` na estacao DEV;
6. executar `npm test`;
7. obter pelo Git a lista de arquivos JavaScript versionados e executar
   `node --check` em cada um;
8. obter pelo Git a lista de scripts PowerShell versionados e usar o parser da
   linguagem para detectar erros de sintaxe;
9. interromper imediatamente a release diante de qualquer falha;
10. emitir um resumo final em portugues, sem imprimir segredos.

## Decisoes de implementacao

- Usar `[CmdletBinding()]` e parametros validados.
- Usar arrays de argumentos ao executar programas nativos.
- Nao montar comandos com entrada concatenada.
- Nao ler nem imprimir `.env`.
- Nao iniciar a aplicacao nem o worker.
- Nao tocar em banco SQLite, servico Windows ou Scheduled Task.
- Nao criar, remover ou publicar tags.
- Nao usar `ExecutionPolicy Bypass`.
- Propagar codigo de saida diferente de zero em qualquer falha.
- Incluir comment-based help completo conforme `docs/patterns.md`.

## Arquivos previstos

```text
deploy/windows/Test-PSPanelRelease.ps1
README.md
src/config/release.js
```

## Fora de escopo

- Alterar `New-PSPanelReleaseTag.ps1`.
- Configurar WinRM ou executar comandos remotos.
- Testar integracoes corporativas reais.
- Fazer deploy ou rollback.
- Atualizar dependencias.

## Validacao obrigatoria

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    'deploy\windows\Test-PSPanelRelease.ps1',
    [ref]$tokens,
    [ref]$errors
) | Out-Null
$errors

.\deploy\windows\Test-PSPanelRelease.ps1
```

Tambem validar que uma falha de teste simulada ou controlada produz codigo de
saida diferente de zero e impede a continuidade do script.

## Criterios de aceite

- Um unico comando executa testes e validacoes de sintaxe da candidata.
- Apenas arquivos versionados sao usados nas varreduras de sintaxe.
- Falha em `npm ci`, `npm test`, JavaScript ou PowerShell interrompe o fluxo.
- O script nao acessa `.env`, bancos, servicos ou recursos externos.
- A saida identifica claramente cada etapa e o resultado final.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

- TASK-056 concluida.
- TASK-057 concluida para que a barreira use a cobertura critica planejada.

---

## Assinatura da LLM

- Data: 2026-08-18 11:23:31 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

Status: implementada em 2026-08-18.

Foi criado `deploy/windows/Test-PSPanelRelease.ps1` como barreira unica para a
estacao DEV. O comando valida estrutura e ferramentas, exige a versao de Node.js
informada, executa `npm ci` e `npm test`, e verifica somente os arquivos
JavaScript e PowerShell rastreados pelo Git. Scripts PowerShell sao apenas
analisados pelo parser e nunca executados.

O fluxo interrompe na primeira falha com codigo de saida diferente de zero,
preserva o estado dos arquivos rastreados e nao inicia aplicacao, worker,
servicos ou tarefas. Tambem nao le `.env`, nao acessa bancos SQLite e nao cria
tags.

Validacoes executadas:

- parser PowerShell do novo script: sem erros;
- fluxo completo em clone temporario isolado: `npm ci`, 47 testes, 66 arquivos
  JavaScript e 18 scripts PowerShell aprovados;
- falha controlada de `npm test` com codigo 23: o validador retornou codigo 1 e
  nao iniciou as etapas seguintes;
- versao de Node.js divergente: bloqueio antes de `npm ci`;
- `git diff --check`.

O clone temporario usado na validacao foi removido. O release foi atualizado
para `v2026.08.18-059`.

---

## Assinatura da LLM

- Data: 2026-08-18 13:32:29 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
