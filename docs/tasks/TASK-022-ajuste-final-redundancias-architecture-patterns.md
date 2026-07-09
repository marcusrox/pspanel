# TASK-022 - Ajuste final de redundancias entre architecture e patterns

## Contexto

A TASK-021 reduziu parte da redundancia entre `docs/architecture.md` e `docs/patterns.md`, separando melhor o papel dos dois documentos:

- `docs/architecture.md`: estrutura e fluxos atuais do sistema.
- `docs/patterns.md`: padroes praticos para implementar mudancas.

Uma revisao adicional identificou que ainda restaram redundancias editoriais e alguns trechos que podem morar melhor em apenas um dos arquivos. A intencao desta task e fazer uma segunda passada pequena e dirigida, sem reescrever a documentacao inteira.

## Objetivo

Eliminar as redundancias restantes mais evidentes entre `docs/architecture.md` e `docs/patterns.md`, mantendo informacoes arquiteturais em `architecture` e orientacoes acionaveis de implementacao em `patterns`.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

- Revisar somente `docs/architecture.md` e `docs/patterns.md`.
- Remover ou consolidar frases duplicadas sobre o papel de cada documento.
- Reduzir a repeticao da estrutura de diretorios em `docs/patterns.md`.
- Remover de `docs/architecture.md` detalhes praticos sobre como incluir o partial da sidebar.
- Reavaliar a secao `Cuidados ao Evoluir` de `docs/patterns.md` para evitar repetir pontos de atencao ja documentados em `docs/architecture.md`.
- Quando um item precisar permanecer em `patterns.md`, reescreve-lo como regra acionavel de implementacao, nao como descricao arquitetural.

## Fora de escopo

- Alterar codigo da aplicacao.
- Alterar arquivos fora de `docs/architecture.md` e `docs/patterns.md`, exceto este arquivo de task.
- Reescrever integralmente os dois documentos.
- Remover informacoes de seguranca uteis apenas para reduzir tamanho.
- Alterar ou apagar tasks anteriores.
- Executar automaticamente a implementacao desta task apos criar o arquivo.

## Arquivos provaveis

```text
docs/architecture.md
docs/patterns.md
```

## Melhorias identificadas

### 1. Nota inicial redundante em `architecture.md`

`docs/architecture.md` possui duas frases consecutivas com funcao parecida:

- `Esse documento pretende responder COMO o sistema é organizado`
- `Este documento descreve a estrutura e os fluxos atuais do sistema. Regras de implementacao ficam em docs/patterns.md.`

Manter apenas a segunda frase, pois ela explica melhor a responsabilidade do arquivo e referencia o documento complementar.

### 2. Estrutura de diretorios ainda duplicada em `patterns.md`

`docs/patterns.md` ainda lista praticamente todos os diretorios principais que ja aparecem na arvore de `docs/architecture.md`.

Manter em `patterns.md` apenas:

- uma frase apontando para `docs/architecture.md` para a estrutura completa;
- o bloco pratico de convencao para novas funcionalidades:

```text
src/routes/<feature>Routes.js
src/controllers/<feature>Controller.js
src/models/<Feature>.js
views/<feature>.ejs
```

Se for necessario manter uma lista curta, ela deve conter apenas orientacoes praticas que nao estejam claras na arquitetura.

### 3. Detalhes do partial da sidebar em `architecture.md`

`docs/architecture.md` informa que telas autenticadas passam `user` e `activeMenu` para `views/partials/sidebar.ejs`. Esse detalhe tambem aparece como orientacao pratica em `docs/patterns.md`.

Manter em `architecture.md` apenas que o menu lateral compartilhado existe em `views/partials/sidebar.ejs`.

Manter em `patterns.md` a orientacao pratica de incluir o partial e passar `user` e `activeMenu`.

### 4. Pontos de atencao repetidos em `patterns.md`

A secao `Cuidados ao Evoluir` de `docs/patterns.md` repete varios pontos ja descritos em `docs/architecture.md`, como:

- `src/app.js` legado;
- `/list-scripts` e `/render-scripts` sem protecao propria;
- `ADMIN_PASSWORD_HASH` existente mas nao usado;
- `LDAP_SEARCH_FILTER` existente mas nao usado;
- arquivos SQLite locais.

Opcoes aceitaveis:

1. Remover esses itens de `patterns.md` e deixar a lista completa em `architecture.md`.
2. Reescrever os itens em `patterns.md` como regras acionaveis, por exemplo:
   - "Ao alterar bootstrap, confirme que o ponto de entrada ativo e `app.js`."
   - "Ao tocar autenticacao, nao assuma que `ADMIN_PASSWORD_HASH` ja esta ativo."
   - "Ao alterar rotas auxiliares, confira explicitamente a protecao de sessao."

Preferir a opcao 2 quando o item for importante para evitar erro de implementacao.

## Sugestao de implementacao

1. Em `docs/architecture.md`, remover a frase antiga `Esse documento pretende responder COMO o sistema é organizado`.
2. Em `docs/patterns.md`, reduzir a lista inicial de diretorios para uma referencia curta a `docs/architecture.md`.
3. Em `docs/architecture.md`, simplificar a secao `Views e partials` para nao explicar os parametros do partial.
4. Em `docs/patterns.md`, revisar `Cuidados ao Evoluir`:
   - remover itens puramente descritivos;
   - manter ou reescrever itens que funcionem como alerta pratico de implementacao.
5. Fazer uma leitura final comparando os dois arquivos para confirmar que:
   - `architecture.md` continua entendivel sozinho como mapa do sistema;
   - `patterns.md` continua util como guia de implementacao;
   - nao foram removidas regras de seguranca necessarias.

## Criterios de aceite

- `docs/architecture.md` nao possui duas frases iniciais redundantes sobre seu proprio papel.
- `docs/patterns.md` nao repete a estrutura de diretorios completa ja documentada em `docs/architecture.md`.
- Detalhes de inclusao do partial da sidebar ficam apenas em `docs/patterns.md`.
- `Cuidados ao Evoluir` em `docs/patterns.md` fica escrito como orientacao pratica, nao como duplicacao de observacoes tecnicas da arquitetura.
- Nenhum codigo da aplicacao e alterado.
- Nenhum arquivo SQLite, `.env`, `.env.example`, `package.json` ou `package-lock.json` e alterado.
- A documentacao resultante continua consistente com o estado atual do projeto.

## Testes sugeridos

- Revisar manualmente `docs/architecture.md`.
- Revisar manualmente `docs/patterns.md`.
- Conferir o diff:

```powershell
git diff -- docs\architecture.md docs\patterns.md
```

- Buscar termos-chave para confirmar que informacoes essenciais continuam presentes em pelo menos um dos documentos:

```powershell
rg -n "sidebar|activeMenu|src/app.js|ADMIN_PASSWORD_HASH|LDAP_SEARCH_FILTER|list-scripts|render-scripts|scripts-ps" docs\architecture.md docs\patterns.md
```

## Validacao esperada

- `git diff -- docs\architecture.md docs\patterns.md`
- Revisao manual dos dois documentos.
- Busca por termos-chave com `rg`.

Se um trecho parecer util nos dois arquivos, manter a versao completa no documento mais pertinente e deixar no outro apenas uma referencia curta ou uma regra pratica.
