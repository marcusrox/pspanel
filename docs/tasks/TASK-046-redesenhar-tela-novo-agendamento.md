# TASK-046 - Redesenhar tela de novo agendamento

## Contexto

A tela autenticada **Novo agendamento**, em `/schedules/new`, concentra todos
os campos em um quadro estreito com largura maxima de aproximadamente 760px.
Em monitores de computador, esse quadro ocupa apenas a parte esquerda da area
disponivel e deixa uma grande faixa vazia a direita.

Depois da introducao da recorrencia cron na TASK-045, o quadro **Quando
executar** passou a conter tipo de agendamento, dias da semana, frequencia,
horario ou intervalo, timezone, expressao cron e proximas ocorrencias. Esse
conteudo tem importancia suficiente para ocupar uma coluna propria no desktop,
em vez de ficar abaixo dos campos do script.

## Objetivo

Redesenhar `views/schedule-form.ejs` para aproveitar melhor a largura disponivel
e tornar o formulario mais claro, moderno e equilibrado:

- configuracao do script e parametros na coluna esquerda;
- configuracao de **Quando executar** na coluna direita;
- acoes finais bem posicionadas e faceis de localizar;
- hierarquia visual apoiada por icones, cores discretas e tipografia;
- layout compacto sem comprometer legibilidade ou acessibilidade;
- retorno automatico para uma unica coluna em telas menores.

O mesmo desenho deve funcionar nos modos **Novo agendamento** e **Editar
agendamento**.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario, conforme
`AGENTS.md`.

## Decisoes de design

- Manter a identidade escura atual do PS Panel.
- Nao redesenhar sidebar, cabecalho global, rodape ou outras paginas.
- Nao adicionar framework CSS, biblioteca de componentes ou nova dependencia.
- Reutilizar Font Awesome, que ja esta carregado na view.
- Usar CSS localizado na propria view, seguindo o padrao atual do projeto.
- Usar a largura disponivel da area principal, com limite confortavel para
  monitores muito largos.
- Priorizar densidade organizada, nao apenas aumentar os componentes.
- Cores devem comunicar agrupamento e estado, sem criar excesso de badges,
  gradientes ou efeitos luminosos.
- A funcionalidade cron implementada pela TASK-045 nao deve ser alterada.

## Estrutura desktop

Remover o `max-width: 760px` que limita o formulario atual e criar um container
principal com largura total, preferencialmente limitado entre `1280px` e
`1440px` para manter boa leitura em monitores ultrawide.

Em desktop, organizar o formulario como grid de duas colunas:

```text
+--------------------------------------+----------------------------------+
| Script e parametros                  | Quando executar                  |
|                                      |                                  |
| Script selecionado                   | Uma vez / Recorrente             |
| Parametros declarados                | Dias e frequencia                |
| Parametros adicionais                | Horario / intervalo              |
|                                      | Timezone, cron e proximas datas  |
+--------------------------------------+----------------------------------+
| Ativo                                      Cancelar    Salvar            |
+-------------------------------------------------------------------------+
```

Diretrizes:

- coluna esquerda ligeiramente maior, aproximadamente `minmax(0, 1.15fr)`;
- coluna direita aproximadamente `minmax(340px, 0.85fr)`;
- gap entre colunas entre `1rem` e `1.5rem`;
- cada coluna deve ser um card visual independente;
- o quadro de recorrencia pode permanecer visivel com `position: sticky` em
  desktop somente se isso nao causar corte, sobreposicao ou problema de
  navegacao por teclado;
- a barra de acoes deve ocupar as duas colunas e permanecer no fluxo normal da
  pagina;
- nao deixar controles isolados em grandes faixas vazias.

## Card de script e parametros

Criar um cabecalho interno para a coluna esquerda com:

- icone de terminal ou codigo;
- titulo **Script e parametros**;
- descricao curta, como `Selecione o script e informe os dados necessarios`.

Organizacao sugerida:

1. seletor de script em destaque no topo;
2. parametros declarados pelo PowerShell em grid responsivo;
3. parametros adicionais ao final, visualmente secundarios.

Melhorias:

- reduzir margens verticais excessivas entre campos relacionados;
- preservar o grid automatico de parametros;
- manter badges de campo obrigatorio, com contraste adequado;
- usar icones pequenos apenas nos titulos ou metadados relevantes;
- manter campos sensiveis e validacoes existentes sem alteracao;
- nao reduzir a area util dos inputs para inserir decoracao.

## Card Quando executar

Transformar o `fieldset` atual em um card de destaque moderado, preservando sua
semantica ou usando `fieldset` dentro do card.

Cabecalho interno:

- icone de calendario ou relogio;
- titulo **Quando executar**;
- descricao curta do tipo de agendamento;
- identificacao visivel do fuso `America/Sao_Paulo`.

### Tipo de agendamento

Apresentar **Uma vez** e **Recorrente** como um seletor segmentado acessivel:

- continuar usando inputs `radio` reais;
- toda a area de cada opcao deve ser clicavel;
- estado selecionado deve combinar borda, fundo e texto, nao depender apenas de
  cor;
- usar icone discreto diferente para execucao unica e recorrente;
- manter foco de teclado claramente visivel.

### Dias e frequencia

- apresentar dias da semana como chips/checkboxes compactos e uniformes;
- destacar **Todos os dias** sem competir visualmente com os dias individuais;
- manter nomes curtos `Dom`, `Seg`, `Ter`, `Qua`, `Qui`, `Sex`, `Sab`;
- distribuir os sete dias sem criar scroll horizontal;
- alinhar frequencia e horario/intervalo em grid quando houver largura;
- manter controles ocultos realmente desabilitados, conforme comportamento
  atual.

### Previa cron

Dar tratamento visual proprio para a previa:

- titulo pequeno com icone de olho ou calendario;
- descricao humana como informacao principal;
- expressao cron em bloco monoespacado compacto;
- proximas ocorrencias em lista curta, com icones ou marcadores discretos;
- diferenciar expressao tecnica e datas por tipografia e cor;
- manter `aria-live="polite"`;
- usar apenas `textContent` para valores dinamicos;
- evitar que expressoes ou datas causem overflow.

## Tipografia, cores e icones

Usar fontes locais e fallbacks do sistema, sem carregar fonte externa nova:

- corpo e inputs: pilha atual ou `Segoe UI Variable`, `Segoe UI`, sans-serif;
- titulos dos cards: peso entre `600` e `700`, tamanho moderado;
- expressao cron: fonte monoespacada existente;
- descricoes: tamanho menor e cor secundaria, sem ficar ilegivel.

Paleta sugerida, adaptada as variaveis existentes:

- azul primario para selecao, foco e acao principal;
- violeta ou azul-violeta muito discreto para o card de agendamento;
- verde somente para indicar estado ativo ou proxima execucao valida;
- vermelho apenas para erros e obrigatoriedade;
- fundos com pequena variacao entre card, campo e previa.

Regras para icones:

- reutilizar classes Font Awesome ja disponiveis;
- icones decorativos devem usar `aria-hidden="true"`;
- nao colocar icone em todos os labels;
- nao usar icone como unica forma de comunicar uma acao ou estado;
- manter tamanho e alinhamento consistentes.

## Barra de acoes

Reorganizar o rodape do formulario:

- checkbox **Ativo** alinhado a esquerda;
- **Cancelar** e **Salvar agendamento** alinhados a direita no desktop;
- botao salvar com icone e texto completo;
- area separada dos cards por borda ou espacamento, sem parecer um terceiro card
  pesado;
- em mobile, permitir quebra de linha e botoes com largura confortavel;
- preservar ordem logica de tabulacao.

Nao tornar a barra fixa na viewport nesta task.

## Responsividade

Definir breakpoints pelo espaco real do conteudo, considerando a sidebar:

- desktop amplo: duas colunas;
- tablet ou janela estreita: uma coluna;
- mobile: uma coluna, padding reduzido e botoes adaptados;
- o card **Quando executar** deve aparecer depois de **Script e parametros** na
  ordem do DOM;
- nenhum card, grid, chip, campo ou bloco cron pode ampliar a pagina
  horizontalmente;
- manter a correcao localizada de largura da `.main-content` introduzida na
  TASK-045;
- testar pelo menos larguras de viewport de `1440`, `1024`, `768` e `390` px.

## Acessibilidade

- Manter exatamente um `h1` visivel.
- Usar `h2` nos titulos principais dos cards.
- Preservar `label` associado a cada input.
- Preservar `fieldset`/`legend` ou fornecer agrupamento semantico equivalente
  para tipo e recorrencia.
- Radios e checkboxes customizados devem continuar operaveis por teclado.
- Estado selecionado nao pode depender somente de cor.
- Foco deve permanecer visivel em todos os elementos interativos.
- Manter contraste de texto, bordas, hints e estados desabilitados.
- Icones decorativos devem usar `aria-hidden="true"`.
- Respeitar `prefers-reduced-motion` caso sejam adicionadas transicoes.
- Nao usar `innerHTML` para montar campos, previa ou mensagens.

## Comportamento que deve ser preservado

- Selecao e leitura dos parametros declarados no script PowerShell.
- Preenchimento dos parametros estruturados e adicionais.
- Validacao de parametros obrigatorios no navegador e no servidor.
- Alternancia entre `once` e `cron`.
- Selecao de dias e atalho **Todos os dias**.
- Cadencias de horario fixo, minutos e horas.
- Geracao e previa da expressao cron.
- Previa das proximas tres ocorrencias.
- Timezone `America/Sao_Paulo`.
- Campos ocultos desabilitados.
- Modo de edicao preenchido com os valores persistidos.
- Checkbox ativo.
- Mascaramento e protecoes de parametros existentes.
- Actions e contratos POST atuais.

## Arquivos provaveis

```text
views/schedule-form.ejs
src/config/release.js
```

Alterar `public/styles.css` somente se uma regra puder ser legitimamente
compartilhada e a mudanca nao afetar outras telas. A preferencia desta task e
manter o CSS localizado em `schedule-form.ejs`.

Nao alterar controller, model, migration, banco, rotas, cron, worker,
`package.json` ou `package-lock.json` para realizar apenas o redesenho.

Ao concluir a implementacao, atualizar `src/config/release.js`, incrementando o
numero sequencial em 1 e usando a data/hora atual do ambiente, conforme
`AGENTS.md`.

## Fora de escopo

- Alterar regras de recorrencia ou formatos cron aceitos.
- Integrar `cron-parser` ao codigo.
- Adicionar novas frequencias ou timezone configuravel.
- Alterar schema ou dados SQLite.
- Redesenhar a lista `/schedules` ou a auditoria.
- Redesenhar sidebar, cabecalho global ou rodape.
- Adicionar framework CSS, fonte externa ou dependencia frontend.
- Criar autosave, wizard em etapas ou modal.
- Tornar a barra de acoes fixa.
- Implementar esta task no mesmo prompt de sua criacao.

## Criterios de aceite

- Em desktop, o formulario utiliza de forma equilibrada a largura disponivel.
- **Script e parametros** aparece na coluna esquerda.
- **Quando executar** aparece na coluna direita.
- A coluna direita nao fica estreita a ponto de quebrar dias, campos ou previa.
- Em tablet/mobile, os cards ficam em uma unica coluna na ordem correta.
- Nao existe overflow horizontal nas larguras testadas.
- O formulario possui hierarquia clara com titulos, descricoes e icones
  moderados.
- Cores reforcam selecao e agrupamento sem excesso visual.
- Tipo `once` mostra apenas data/hora e desabilita recorrencia.
- Tipo `cron` mostra dias, frequencia, configuracao e previa.
- O exemplo segunda-feira a cada 5 minutos continua gerando `*/5 * * * 1`.
- A previa continua mostrando descricao e tres proximas ocorrencias.
- Todos os campos e botoes permanecem acessiveis por teclado.
- O modo de edicao preserva script, parametros, tipo e recorrencia.
- Nenhuma regra de controller, model, schema ou worker e alterada.
- Nenhuma dependencia ou lockfile e alterado por esta task.
- O controle de release e atualizado somente ao concluir a implementacao.

## Testes sugeridos

### Validacao de template e JavaScript

- compilar `views/schedule-form.ejs` com EJS;
- renderizar os modos novo, editar `once` e editar `cron` com fixtures seguras;
- validar a sintaxe do JavaScript inline;
- executar `test/scheduleViews.test.js`;
- confirmar que nenhuma referencia a `repeat_interval_minutes` foi reintroduzida.

### Validacao funcional

- alternar entre **Uma vez** e **Recorrente**;
- confirmar visibilidade, `required` e `disabled` dos controles;
- selecionar todos os dias e dias individuais;
- alternar horario fixo, minutos e horas;
- validar a expressao `*/5 * * * 1`;
- trocar scripts e confirmar renderizacao dos parametros;
- testar alerta de parametro obrigatorio;
- confirmar que os payloads POST permanecem inalterados.

### Validacao visual

Na porta `3100` ou proxima livre, nunca na porta `3000`:

- conferir desktop em `1440px`, com cards lado a lado;
- conferir janela intermediaria em `1024px`;
- conferir breakpoint em `768px`;
- conferir mobile em `390px`;
- verificar alinhamento, densidade, espacamentos, icones e contraste;
- verificar campos longos, muitos parametros e descricao cron extensa;
- confirmar ausencia de overflow horizontal;
- testar zoom de navegador em `200%`;
- navegar pelo formulario somente com teclado;
- confirmar foco visivel e ordem logica;
- capturar o PID do servidor temporario e encerrar somente esse processo.

## Validacao esperada na implementacao

- Executar `node --test test/scheduleViews.test.js`.
- Compilar a view EJS e validar o JavaScript inline.
- Fazer validacao HTTP autenticada local.
- Fazer validacao visual nos quatro tamanhos definidos.
- Executar `git diff --check`.
- Confirmar que somente a view, testes estritamente necessarios, documentacao da
  task e release foram alterados por esta implementacao.
- Confirmar que nenhum banco, `.env`, arquivo operacional, dependencia ou
  lockfile foi alterado pela TASK-046.

---

## Assinatura da LLM

- Data: 17/07/2026 18:11:30
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
