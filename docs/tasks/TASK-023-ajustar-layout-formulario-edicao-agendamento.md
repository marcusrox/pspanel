# TASK-023 - Ajustar layout do formulario de agendamento

## Contexto

No formulario de agendamento (`views/schedule-form.ejs`), usado para novo e editar agendamento, os campos abaixo aparecem em linhas separadas:

- `Primeira / próxima execução (horário local)`, campo `next_run_at`;
- `Repetir a cada (minutos)`, campo `repeat_interval_minutes`.

No formulário de schedule, esses dois campos fazem parte do mesmo bloco conceitual de programacao da execucao e podem ocupar melhor o espaco horizontal ficando lado a lado em desktop.

Tambem existe um checkbox `Ativo`, hoje renderizado dentro de um `label` simples:

```ejs
<label><input type="checkbox" name="enabled" value="1" ...> Ativo</label>
```

Com o estilo atual de `.form-group label`, o checkbox fica visualmente centralizado/distante do texto correspondente, prejudicando leitura e clique.

## Objetivo

Ajustar o layout do formulario de schedule para:

1. colocar lado a lado os campos `Primeira / próxima execução (horário local)` e `Repetir a cada (minutos)` em telas com largura suficiente;
2. manter esses campos empilhados em telas pequenas;
3. alinhar melhor o checkbox `Ativo` ao label correspondente, deixando o controle visualmente proximo do texto.


## Escopo

- Alterar apenas o layout da view `views/schedule-form.ejs`, salvo se algum estilo global claramente precisar de ajuste pontual.
- Criar uma classe local para agrupar os campos `next_run_at` e `repeat_interval_minutes` em grid responsivo.
- Preservar labels, nomes, ids e valores dos campos.
- Preservar o texto de ajuda de `repeat_interval_minutes`.
- Criar uma classe local para o checkbox `Ativo`, com alinhamento horizontal compacto entre input e texto.
- Garantir que o layout continue responsivo em largura pequena.
- Manter idioma pt-BR e padrao visual existente do painel.

## Fora de escopo

- Alterar regras de criacao/edicao de schedules.
- Alterar controller, model, rotas ou schema.
- Alterar nomes de campos enviados no formulario.
- Alterar semantica de `next_run_at`, `repeat_interval_minutes` ou `enabled`.
- Modificar o worker de agendamentos.
- Reescrever a tela inteira ou alterar estilos globais sem necessidade.
- Executar automaticamente a implementacao desta task apos criar o arquivo.

## Arquivos provaveis

```text
views/schedule-form.ejs
```

Se houver necessidade real de ajustar CSS compartilhado, avaliar com cuidado antes de alterar:

```text
public/styles.css
```

## Requisitos funcionais

1. Em telas desktop/tablet largas, `Primeira / próxima execução (horário local)` e `Repetir a cada (minutos)` devem aparecer lado a lado.
2. Em telas estreitas, os dois campos devem voltar a ficar empilhados, sem sobreposicao.
3. O campo `Repetir a cada (minutos)` deve continuar exibindo sua dica explicativa.
4. O checkbox `Ativo` deve ficar proximo do texto `Ativo`, alinhado de forma natural.
5. Clicar no texto `Ativo` deve continuar alternando o checkbox.
6. O formulario deve continuar enviando os mesmos campos:
   - `next_run_at`;
   - `repeat_interval_minutes`;
   - `enabled`.
7. A alteracao deve valer para o formulario compartilhado sem quebrar o modo novo agendamento.

## Requisitos visuais

- Usar grid ou flex local na view, sem criar card dentro de card.
- Evitar largura fixa que quebre em mobile.
- Manter espacamento consistente com `.form-group`.
- Evitar que o texto longo `Primeira / próxima execução (horário local)` sobreponha o campo ao lado.
- Manter o checkbox com dimensao nativa ou estilo discreto, sem parecer botao.

## Sugestao de implementacao

1. Adicionar um wrapper ao redor dos dois `.form-group` de data e repeticao, por exemplo:

```html
<div class="schedule-time-grid">
    ...
</div>
```

2. Criar CSS local em `views/schedule-form.ejs`:

```css
.schedule-time-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 1rem;
}
```

3. Ajustar margem dos `.form-group` internos se necessario para evitar espaco duplicado.
4. Trocar o label simples do checkbox por uma estrutura mais controlada, por exemplo:

```html
<label class="checkbox-field">
    <input type="checkbox" name="enabled" value="1" ...>
    <span>Ativo</span>
</label>
```

5. Criar CSS local:

```css
.checkbox-field {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
}
```

6. Se a regra global `.form-group label` interferir no checkbox, usar seletor local para neutralizar apenas nesse caso.

## Criterios de aceite

- Os campos `next_run_at` e `repeat_interval_minutes` aparecem lado a lado em largura desktop.
- Os campos ficam empilhados em mobile ou largura estreita.
- O checkbox `Ativo` fica visualmente proximo do texto.
- Clicar no texto `Ativo` continua acionando o checkbox.
- O formulario continua submetendo os mesmos nomes de campos.
- Nao ha alteracao de comportamento no backend.
- A mudanca fica localizada principalmente em `views/schedule-form.ejs`.

## Testes sugeridos

- Renderizar `views/schedule-form.ejs` com dados simulados para confirmar que a view nao quebrou.
- Abrir `/schedules/:id/edit` e conferir visualmente:
  - campos de horario/repeticao lado a lado em desktop;
  - campos empilhados em largura pequena;
  - checkbox `Ativo` alinhado ao label.
- Abrir `/schedules/new` para garantir que o formulario compartilhado tambem continua correto.
- Salvar um agendamento sem alterar comportamento dos campos.

## Validacao esperada

- Validacao visual de `/schedules/:id/edit`.
- Validacao visual de `/schedules/new`.
- Renderizacao EJS de `views/schedule-form.ejs`, se pratico.

Se a validacao visual exigir login, usar credenciais locais apenas quando ja fornecidas/autorizadas pelo usuario; nunca imprimir ou documentar valores do `.env`.
