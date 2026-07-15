# TASK-038 - Mascarar senhas na tela de agendamentos

## Contexto

A tela de Agendamentos (`/schedules`) renderiza atualmente o conteudo persistido em `schedules.parameters` em dois pontos:

- na coluna `Parâmetros` da tabela;
- no campo `Parâmetros` do modal `Detalhes da última execução`.

O mesmo modal tambem exibe `last_run_output`. Caso um script escreva na saida o valor de um parametro sensivel, a senha pode aparecer novamente na area `Saída`.

Com isso, parametros como `-FortiPassword`, `-Password`, `-Senha`, `-SenhaAdmin` ou qualquer outro cujo nome contenha `senha` ou `password` podem expor o valor salvo para usuarios que acessam a listagem. Os valores tambem sao colocados atualmente em atributos `data-*` do botao de detalhes, portanto apenas trocar o texto visivel por asteriscos nao elimina a exposicao no HTML entregue ao navegador.

## Objetivo

Mascarar, na resposta HTML da tela `/schedules`, os valores de todos os parametros cujo nome contenha `senha` ou `password`, sem diferenciar maiusculas de minusculas, incluindo eventuais repeticoes desses valores em `Detalhes da última execução`.

A protecao deve impedir que o valor original chegue ao navegador nessa tela, preservando os dados reais no banco e o uso dos argumentos pelo worker.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Regra de identificacao

Um parametro deve ser considerado sensivel quando seu nome contiver uma destas strings, em qualquer posicao e sem diferenciar maiusculas de minusculas:

```text
senha
password
```

Exemplos que devem ser identificados:

```text
-Senha valor
-SenhaAdmin valor
-FortiPassword valor
-password valor
-DatabasePassword "valor com espacos"
```

Exemplos que nao devem ser mascarados por esta regra:

```text
-Usuario admin
-Servidor srv01
-Token valor
```

## Escopo

- Mascarar os valores sensiveis na coluna `Parâmetros` da listagem `/schedules`.
- Mascarar os mesmos valores no campo `Parâmetros` do modal `Detalhes da última execução`.
- Remover valores sensiveis dos atributos `data-*`, do HTML inline e de qualquer estrutura JavaScript enviada para essa tela.
- Mascarar na area `Saída` do modal as ocorrencias dos valores extraidos de parametros identificados como sensiveis.
- Preservar o nome do parametro para manter o contexto, substituindo somente seu valor por uma mascara fixa, por exemplo `********`.
- Tratar nomes de parametros de forma case-insensitive.
- Tratar parametros conhecidos pelo parser do script e parametros adicionais escritos no formato nomeado.
- Manter suporte aos valores entre aspas e com espacos conforme o tokenizer atual.
- Reutilizar uma funcao centralizada de mascaramento para evitar regras diferentes entre a tabela e o modal.
- Atualizar o controle de release em `src/config/release.js` quando a task for implementada, conforme `AGENTS.md`.

## Fora de escopo

- Criptografar ou alterar o valor persistido em `database/schedules.sqlite`.
- Substituir a senha real antes da execucao do PowerShell.
- Alterar a montagem dos argumentos ou o comportamento do worker.
- Alterar o formulario `/schedules/new` ou `/schedules/:id/edit`.
- Mascarar parametros em `/history`, auditoria, logs operacionais ou outras telas nesta task.
- Ampliar automaticamente a deteccao para nomes como `token`, `secret`, `key`, `credential` ou equivalentes.
- Alterar scripts `.ps1`.
- Alterar schema ou migrar dados SQLite.
- Adicionar dependencia externa.

## Arquivos provaveis

```text
src/controllers/scheduleController.js
src/services/powerShellParameters.js
views/schedules.ejs
src/config/release.js
```

Se a transformacao puder ser aplicada de forma segura e pequena no controller usando um helper compartilhado, nao alterar `src/models/Schedule.js`. O model deve continuar retornando e executando com os valores reais.

## Requisitos funcionais

1. A listagem deve continuar mostrando o nome de cada parametro.
2. O valor de todo parametro cujo nome contenha `senha` ou `password` deve aparecer como uma mascara fixa.
3. A deteccao deve funcionar para qualquer combinacao de maiusculas e minusculas, incluindo `FortiPassword`, `fortipassword`, `SENHA` e `SenhaAdmin`.
4. Parametros nao sensiveis devem continuar sendo exibidos sem alteracao.
5. O modal deve mostrar a mesma versao mascarada dos parametros apresentada na tabela.
6. Se `last_run_output` contiver o valor real de um parametro sensivel, todas as ocorrencias literais desse valor devem ser substituidas pela mesma mascara antes da renderizacao.
7. A saida sem ocorrencias sensiveis deve permanecer inalterada.
8. Valores vazios nao devem causar substituicoes indevidas.
9. Parametros do tipo switch, sem valor explicito, nao devem provocar mascaramento de textos genericos como `true` ou `false` na saida.
10. Valores sensiveis entre aspas ou contendo espacos devem ser mascarados integralmente na exibicao dos parametros e na saida.
11. O valor real deve permanecer salvo e deve continuar sendo enviado ao script durante a execucao agendada.
12. Editar, excluir e abrir detalhes deve continuar funcionando como antes.

## Requisitos de seguranca

- Fazer o mascaramento no servidor antes de renderizar `views/schedules.ejs`; mascaramento apenas visual por CSS ou JavaScript nao e suficiente.
- Garantir que valores sensiveis nao aparecam no HTML retornado por `/schedules`, inclusive em:
  - celulas da tabela;
  - atributos `data-parameters` e `data-output`;
  - objetos JSON ou scripts inline;
  - campos ocultos ou comentarios HTML.
- Nao registrar em novos logs os parametros originais, a lista de valores sensiveis extraidos ou a saida anterior ao mascaramento.
- Manter o uso de `<%= ... %>` e `textContent` para evitar XSS.
- Nao usar a mascara para persistencia nem para executar o script.
- Nao alterar o objeto original retornado pelo model se ele puder ser reutilizado em outro ponto do fluxo; criar uma representacao segura especifica para exibicao.
- A mascara deve ter tamanho fixo para nao revelar o comprimento aproximado da senha.

## Requisitos tecnicos

- Manter CommonJS (`require`, `module.exports`).
- Preferir helpers pequenos e testaveis no service existente `src/services/powerShellParameters.js`, por exemplo para:
  - identificar nome sensivel;
  - localizar pares nome/valor no texto de parametros;
  - produzir parametros mascarados;
  - extrair apenas em memoria os valores que precisam ser removidos da saida;
  - produzir uma copia mascarada de `last_run_output`.
- Reaproveitar `tokenizePowerShellArgs` ou evolui-lo de forma compativel, evitando um segundo parser divergente.
- Preservar a ordem e os nomes dos parametros na string exibida sempre que possivel.
- Considerar pelo menos o formato atualmente persistido pelo projeto:

```text
-Nome valor -FortiPassword segredo -Ambiente PROD
```

- Preservar corretamente valores com espacos delimitados por aspas.
- Ao substituir valores na saida, tratar o valor como texto literal, escapando metacaracteres caso seja usada expressao regular.
- Aplicar substituicoes do maior valor para o menor quando houver valores sensiveis sobrepostos.
- Deduplicar valores antes de processar a saida.
- Ignorar valores vazios e valores booleanos implicitos de switches na redacao da saida.
- Manter os fallbacks atuais `—`, `Nenhum` e `Sem saída registrada`.
- Manter mensagens e textos visiveis em portugues.

## Sugestao de implementacao

1. Adicionar ao service de parametros um helper que reconheca nomes por uma regra equivalente a:

```text
/(senha|password)/i
```

2. Tokenizar a string persistida preservando informacao suficiente para reconstruir uma versao de exibicao.
3. Ao encontrar um token nomeado sensivel, manter `-NomeDoParametro` e trocar o proximo valor por `********`.
4. Coletar os valores reais identificados somente em memoria para redigir a saida.
5. No controller da listagem, mapear cada agendamento para uma representacao de view contendo, por exemplo:
   - parametros seguros para exibicao;
   - saida da ultima execucao ja redigida.
6. Renderizar em `views/schedules.ejs` apenas os campos seguros, tanto na tabela quanto nos atributos usados pelo modal.
7. Manter os campos reais isolados do objeto enviado a view sempre que possivel, reduzindo o risco de uso acidental futuro.
8. Atualizar `src/config/release.js` ao concluir a implementacao.

## Casos de exemplo

Entrada persistida:

```text
-FortiUser admin -FortiPassword MinhaSenha123 -Ambiente PROD
```

Exibicao esperada:

```text
-FortiUser admin -FortiPassword ******** -Ambiente PROD
```

Saida persistida da execucao:

```text
Autenticando admin com MinhaSenha123
Conexao concluida.
```

Saida esperada no modal:

```text
Autenticando admin com ********
Conexao concluida.
```

Exemplo com valor entre aspas:

```text
-DatabasePassword "senha com espacos" -Servidor db01
```

Exibicao esperada:

```text
-DatabasePassword ******** -Servidor db01
```

## Criterios de aceite

- Nenhum valor associado a parametro com `senha` ou `password` aparece visualmente na tabela `/schedules`.
- Nenhum desses valores aparece no campo `Parâmetros` do modal.
- Ocorrencias dos valores sensiveis nao aparecem na area `Saída` do modal.
- Inspecionar o HTML retornado, o DOM e os atributos `data-*` nao revela os valores protegidos.
- `FortiPassword` e mascarado corretamente.
- A regra funciona independentemente de maiusculas e minusculas e quando a string aparece no meio do nome.
- Parametros comuns continuam legiveis e com seus valores originais.
- Valores com espacos e aspas sao protegidos.
- A mascara possui comprimento fixo.
- O banco continua contendo o valor real e o worker continua executando com ele.
- Acoes de visualizar, editar e excluir continuam operacionais.
- O release exibido pela aplicacao e atualizado quando a task for implementada.

## Testes sugeridos

- Criar ou usar um agendamento com `-FortiPassword segredo` e confirmar a mascara na tabela.
- Testar nomes `-Senha`, `-SenhaAdmin`, `-password`, `-PASSWORD` e `-DatabasePassword`.
- Confirmar que `-Usuario`, `-Servidor` e `-Ambiente` continuam visiveis.
- Testar um valor sensivel entre aspas e com espacos.
- Testar dois parametros sensiveis diferentes no mesmo agendamento.
- Testar dois parametros sensiveis com o mesmo valor.
- Testar um valor com caracteres especiais de expressao regular, como `a.b+$[1]`.
- Gravar uma saida que contenha o valor sensivel mais de uma vez e confirmar que todas as ocorrencias sao mascaradas.
- Confirmar que uma saida sem o valor sensivel permanece identica.
- Confirmar que valores vazios e switches nao removem palavras genericas da saida.
- Inspecionar o codigo-fonte da resposta e os atributos do botao `Ver detalhes` para confirmar que o segredo real nao foi enviado.
- Executar o agendamento e confirmar que o script recebe o valor verdadeiro, nao `********`.
- Confirmar que o formulario de edicao continua carregando conforme o comportamento anterior.

## Validacao esperada

- Rodar `node --check` nos arquivos JavaScript alterados:

```powershell
node --check src\controllers\scheduleController.js
node --check src\services\powerShellParameters.js
node --check src\config\release.js
```

- Compilar a view EJS:

```powershell
node -e "const fs=require('fs'); const ejs=require('ejs'); ejs.compile(fs.readFileSync('views/schedules.ejs','utf8'), {filename:'views/schedules.ejs'}); console.log('EJS OK');"
```

- Validar visualmente `/schedules` autenticado e o modal `Detalhes da última execução`.
- Inspecionar o HTML/DOM da tela para confirmar que os valores sensiveis nao chegaram ao navegador.
- Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.

Se a validacao visual exigir login, usar credenciais locais apenas quando ja fornecidas ou autorizadas e nunca imprimir valores do `.env`.

---

## Assinatura da LLM

- Data: 2026-07-15 11:28:28 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
