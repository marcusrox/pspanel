# TASK-012 - Exibir saida de agendamento em detalhes

## Contexto

A tela de Agendamentos (`/schedules`) exibe atualmente uma coluna chamada `Saída (resumo)` na listagem principal.

Essa coluna mostra um recorte de `last_run_output`, junto do codigo de saida quando `last_run_exit_code` existe. Como a saida de scripts pode ser longa, a coluna ocupa espaco horizontal importante e deixa a tabela mais carregada, principalmente em telas menores.

A tela de Historico de Execucoes (`/history`) ja possui um padrao mais adequado para esse tipo de informacao: a tabela mostra um botao compacto `Ver detalhes`, com icone de olho, que abre uma visualizacao em modal/alert bonito contendo os dados completos da execucao e a saida em uma area dedicada.

## Objetivo

Remover a coluna `Saída (resumo)` da listagem de Agendamentos e adicionar um terceiro icone na coluna de acoes para visualizar essas informacoes em um modal/alert de detalhes, seguindo o padrao visual existente na tela de Historico de Execucoes.

## Escopo

- Remover da tabela de `views/schedules.ejs` o cabecalho `Saída (resumo)`.
- Remover da tabela a celula inline que exibe o resumo de `s.last_run_output`.
- Adicionar um terceiro botao/icone na coluna `Ações` da listagem de agendamentos.
- O novo botao deve representar `Ver detalhes`, preferencialmente com icone Font Awesome `fas fa-eye`, como em `views/history.ejs`.
- Ao clicar no novo botao, exibir as informacoes que antes apareciam na coluna `Saída (resumo)`.
- Exibir tambem o codigo da ultima execucao quando `last_run_exit_code` existir.
- Usar um modal/alert bonito e consistente com o modal de detalhes da tela de Historico de Execucoes.
- Manter os botoes de acoes compactos, alinhados e responsivos.

## Fora de escopo

- Alterar regras de execucao de agendamentos.
- Alterar worker, model ou persistencia de agendamentos.
- Alterar historico de execucoes.
- Criar nova rota de backend, salvo se a implementacao optar por carregar detalhes sob demanda e isso for realmente necessario.
- Mudar os campos gravados em `database/schedules.sqlite`.
- Reestruturar toda a tabela de agendamentos.
- Alterar o comportamento dos botoes Editar e Excluir.
- Implementar filtros, paginacao ou busca na tela de Agendamentos.

## Arquivos provaveis

```text
views/schedules.ejs
```

Referencia visual:

```text
views/history.ejs
```

Possivelmente tambem:

```text
public/styles.css
```

Somente se houver estilo reutilizavel que faca sentido fora da view. Caso contrario, manter CSS local em `views/schedules.ejs`, seguindo o padrao existente.

## Referencias visuais

Na tela de Historico de Execucoes, usar como referencia:

```text
views/history.ejs
```

Elementos relevantes:

```text
button.icon-btn[title="Ver detalhes"]
detailsModal
modal-content
output-container
showDetails(id)
closeModal()
```

Na tela de Agendamentos, considerar a estrutura atual:

```text
views/schedules.ejs
```

Elementos relevantes:

```text
schedule-actions-cell
schedule-action-buttons
schedule-action-btn
schedule-delete-btn
last_run_output
last_run_exit_code
```

## Requisitos funcionais

1. A coluna `Saída (resumo)` nao deve mais aparecer na tabela de Agendamentos.
2. A tabela deve continuar exibindo as demais colunas atuais.
3. Cada linha da tabela deve ter tres acoes:
   - Ver detalhes;
   - Editar;
   - Excluir.
4. O novo botao `Ver detalhes` deve exibir a saida da ultima execucao do agendamento.
5. Quando houver `last_run_exit_code`, o modal/alert deve mostrar o codigo da ultima execucao.
6. Quando nao houver saida gravada, o modal/alert deve mostrar um fallback amigavel, por exemplo `Sem saída registrada`.
7. O botao Editar deve continuar levando para `/schedules/:id/edit`.
8. O botao Excluir deve continuar enviando `POST` para `/schedules/:id/delete`.
9. A confirmacao de exclusao deve continuar funcionando.
10. O usuario nao deve perder informacao que antes estava na coluna removida; ela deve ficar acessivel pelo novo botao.

## Requisitos tecnicos

- Reaproveitar o padrao visual da tela `views/history.ejs` sempre que possivel.
- Usar Font Awesome ja existente na view; nao adicionar nova biblioteca de icones.
- Manter `pt-BR` nos textos visiveis.
- Usar `<%= ... %>` para saida escapada em EJS.
- Evitar renderizar `last_run_output` como HTML confiavel.
- Se a saida for inserida dinamicamente via JavaScript, garantir escape adequado para evitar XSS vindo da saida do PowerShell.
- Evitar concatenar HTML com valores nao confiaveis sem sanitizacao.
- Manter o layout da coluna `Ações` com `display: flex`, `align-items: center` e `gap`, seguindo a melhoria da TASK-011.
- Garantir que tres icones caibam na coluna de acoes sem sobreposicao.
- O modal/alert deve ser fechavel por botao e, se seguir o padrao de `history`, tambem ao clicar fora.

## Sugestao de implementacao

1. Remover o `th` da coluna `Saída (resumo)` em `views/schedules.ejs`.
2. Remover o `td` que hoje mostra:

```text
s.last_run_output
s.last_run_exit_code
```

3. Adicionar um botao antes de Editar na coluna `Ações`:

```html
<button type="button" class="schedule-action-btn" title="Ver detalhes" aria-label="Ver detalhes da ultima execucao">
    <i class="fas fa-eye" aria-hidden="true"></i>
</button>
```

4. Criar ou reaproveitar um modal na propria view para exibir:
   - script;
   - parametros, se util;
   - ultima execucao;
   - codigo de saida;
   - saida completa ou fallback.
5. Preferir guardar os dados em atributos `data-*` escapados ou em uma estrutura JSON segura gerada pelo EJS.
6. Se usar JavaScript para montar conteudo, criar uma funcao pequena para escapar texto antes de inserir no DOM ou usar `textContent`.

## Criterios de aceite

- A coluna `Saída (resumo)` nao aparece mais na listagem de Agendamentos.
- A coluna `Ações` passa a mostrar tres icones por linha.
- O novo icone `Ver detalhes` abre um modal/alert visualmente consistente com o da tela Historico de Execucoes.
- O modal/alert mostra a saida que antes aparecia na coluna removida.
- O codigo da ultima execucao aparece quando disponivel.
- Agendamentos sem saida exibem fallback amigavel.
- Editar e Excluir continuam funcionando como antes.
- A confirmacao de exclusao continua aparecendo.
- A tabela fica mais limpa e nao apresenta sobreposicao em telas menores.
- Nenhum comportamento de backend e alterado sem necessidade.

## Testes sugeridos

- Abrir `/schedules` autenticado e confirmar que a coluna `Saída (resumo)` foi removida.
- Confirmar que cada linha exibe tres icones na coluna `Ações`.
- Clicar em `Ver detalhes` em um agendamento com `last_run_output` e confirmar que a saida aparece corretamente.
- Clicar em `Ver detalhes` em um agendamento sem saida e confirmar o fallback.
- Confirmar que o codigo de saida aparece quando `last_run_exit_code` existe.
- Fechar o modal pelo botao de fechar.
- Se implementado, fechar o modal clicando fora dele.
- Clicar em Editar e confirmar que a tela de edicao abre normalmente.
- Clicar em Excluir, cancelar a confirmacao e confirmar que o registro permanece.
- Reduzir a largura da janela e confirmar que os tres icones nao se sobrepoem.

## Validacao esperada

- Como a mudanca deve ser em view/CSS, validar visualmente a tela `/schedules` com o servidor em execucao quando possivel.
- Se algum JavaScript externo for alterado, rodar `node --check` no arquivo alterado.
- Se a alteracao ficar apenas em EJS/CSS inline da view, nao ha validacao de sintaxe Node obrigatoria.
- Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.
