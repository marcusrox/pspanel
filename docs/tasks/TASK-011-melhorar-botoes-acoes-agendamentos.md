# TASK-011 - Melhorar botoes de acoes na listagem de agendamentos

## Contexto

A tela de Agendamentos (`/schedules`) possui uma listagem com duas acoes por registro: editar e excluir.

Atualmente, os botoes aparecem visualmente estranhos na tabela. O botao de editar e um link com `icon-btn`, enquanto o botao de excluir fica dentro de um formulario inline com estilos aplicados diretamente no elemento. Isso deixa o conjunto menos consistente do que os botoes de acao usados na listagem de scripts da tela principal.

Na tela principal (`views/index.ejs`), a listagem de scripts ja possui botoes de acao compactos, alinhados e com aparencia mais polida. A melhoria deve aproximar os botoes de Agendamentos desse padrao visual, mantendo o comportamento atual.

## Objetivo

Melhorar a aparencia dos botoes Editar e Excluir na listagem de Agendamentos, mantendo os dois botoes na mesma linha e alinhando o visual ao padrao de botoes existente na listagem de scripts da tela principal.

## Escopo

- Ajustar a marcacao e/ou CSS dos botoes de acoes em `views/schedules.ejs`.
- Manter as acoes Editar e Excluir lado a lado na mesma linha.
- Reaproveitar ou aproximar o estilo dos botoes de acao da listagem de scripts em `views/index.ejs`.
- Remover estilos inline desnecessarios do botao Excluir, se possivel.
- Preservar a confirmacao visual antes de excluir um agendamento.
- Garantir que o formulario de exclusao nao quebre o alinhamento dos botoes.
- Manter responsividade e legibilidade em larguras menores.

## Fora de escopo

- Alterar rotas de backend.
- Alterar controller, model ou regras de negocio de agendamentos.
- Mudar o comportamento de edicao ou exclusao.
- Adicionar novas acoes na listagem.
- Reestruturar toda a tabela de agendamentos.
- Alterar o visual global do painel alem do necessario para esta listagem.

## Arquivos provaveis

```text
views/schedules.ejs
```

Possivelmente tambem:

```text
public/styles.css
```

Somente se o ajuste fizer sentido como estilo reutilizavel. Caso contrario, manter o CSS local da propria view, seguindo o padrao existente.

## Referencias visuais

Usar como referencia a listagem de scripts da tela principal:

```text
views/index.ejs
```

Classes relevantes:

```text
.script-actions-cell
.script-action-buttons
.source-view-btn
.rename-script-btn
```

Tambem considerar o estilo global atual:

```text
public/styles.css
.icon-btn
```

## Requisitos funcionais

1. Cada linha da listagem de Agendamentos deve continuar exibindo as acoes Editar e Excluir.
2. Os botoes Editar e Excluir devem permanecer na mesma linha.
3. Clicar em Editar deve continuar levando para `/schedules/:id/edit`.
4. Clicar em Excluir deve continuar enviando `POST` para `/schedules/:id/delete`.
5. A exclusao deve continuar exigindo confirmacao via `confirm('Excluir este agendamento?')` ou comportamento equivalente ja existente.
6. O visual dos botoes deve ficar consistente, compacto e alinhado com os botoes da listagem principal de scripts.

## Requisitos tecnicos

- Preferir um container de acoes dedicado, por exemplo:

```html
<div class="schedule-action-buttons">
    ...
</div>
```

- Garantir alinhamento horizontal com `display: flex`, `align-items: center` e `gap`.
- Normalizar link e botao para terem a mesma largura/altura visual.
- Evitar `style="..."` inline no formulario e no botao, salvo se houver motivo pontual.
- Fazer o formulario de exclusao se comportar como item inline/flex sem margem extra.
- Manter icones Font Awesome ja usados na view:
  - `fas fa-edit`;
  - `fas fa-trash`.
- Usar `<%= ... %>` para valores EJS, mantendo saida escapada.
- Nao adicionar nova biblioteca de icones ou CSS.
- Nao alterar a ordem das rotas de `scheduleRoutes.js`, pois a mudanca e apenas visual.

Exemplo de direcao de CSS:

```css
.schedule-action-buttons {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    justify-content: flex-end;
}

.schedule-action-buttons form {
    margin: 0;
}

.schedule-action-btn {
    width: 2rem;
    height: 2rem;
    display: inline-flex;
    align-items: center;
    justify-content: center;
}
```

O exemplo e apenas uma direcao. A implementacao final deve respeitar o visual real do painel e evitar duplicacao desnecessaria.

## Criterios de aceite

- Os botoes Editar e Excluir aparecem lado a lado em cada linha da tabela.
- Os dois botoes possuem dimensao, alinhamento e espacamento consistentes.
- O botao Excluir nao parece visualmente separado ou desalinhado por causa do formulario.
- A aparencia fica mais proxima dos botoes de acao da listagem de scripts da tela principal.
- A confirmacao de exclusao continua funcionando.
- A edicao de agendamento continua funcionando.
- A tela nao apresenta sobreposicao ou quebra visual em largura pequena.
- Nenhum comportamento de backend e alterado.

## Testes sugeridos

- Abrir `/schedules` autenticado e verificar a coluna de acoes.
- Confirmar que Editar e Excluir aparecem na mesma linha para todos os registros.
- Clicar em Editar e confirmar que a tela de edicao abre normalmente.
- Clicar em Excluir e confirmar que a caixa de confirmacao aparece.
- Cancelar a exclusao e confirmar que o registro permanece na listagem.
- Confirmar que o alinhamento permanece correto quando a tabela possui nomes de scripts ou parametros longos.
- Reduzir a largura da janela e confirmar que os botoes nao se sobrepoem a outros textos.

## Validacao esperada

- Como a mudanca deve ser em view/CSS, validar visualmente a tela `/schedules` com o servidor em execucao quando possivel.
- Se algum JavaScript for alterado, rodar `node --check` no arquivo alterado.
- Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.
