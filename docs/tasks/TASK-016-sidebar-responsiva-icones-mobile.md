# TASK-016 - Sidebar responsiva com icones em telas pequenas

## Contexto

Em telas pequenas, o menu lateral pode sobrepor textos ao conteudo principal da pagina. O CSS global ja tenta reduzir a sidebar para `64px` abaixo de `768px` e esconder alguns textos, mas a regra atual espera que os rotulos dos links estejam dentro de `span`.

No partial atual da sidebar, os textos dos links estao soltos no HTML:

```ejs
<i class="fas fa-code"></i> Scripts
```

Como nao existe `span` envolvendo esses rotulos, a regra responsiva abaixo nao consegue ocultar os textos do menu:

```css
.sidebar-nav a span {
    display: none;
}
```

O mesmo cuidado vale para o link de logout, onde o texto `Sair` tambem deve poder ser ocultado em modo compacto.

## Objetivo

Evitar sobreposicao entre o menu lateral e o conteudo da pagina em telas pequenas, transformando a sidebar em modo compacto com apenas icones quando a largura da tela for reduzida.

## Escopo

- Ajustar o HTML do partial da sidebar para permitir ocultar textos via CSS.
- Manter icones visiveis no menu lateral em telas pequenas.
- Ocultar rotulos dos links de navegacao em telas pequenas.
- Ocultar informacoes textuais do usuario no rodape em telas pequenas.
- Ocultar o texto `Sair` em telas pequenas, mantendo o icone de logout.
- Ajustar alinhamento e espacamentos da sidebar compacta.
- Manter o conteudo principal deslocado corretamente pela largura compacta da sidebar.
- Preservar idioma `pt-BR` e visual operacional existente.

## Fora de escopo

- Criar menu hamburguer.
- Criar drawer, overlay ou sidebar recolhivel por JavaScript.
- Alterar rotas, controllers, models ou regras de autenticacao.
- Adicionar novos itens ao menu.
- Remover itens existentes do menu.
- Trocar Font Awesome ou adicionar biblioteca de icones.
- Refatorar layout global das views.
- Alterar comportamento de logout.
- Reorganizar CSS nao relacionado.

## Arquivos provaveis

```text
views/partials/sidebar.ejs
public/styles.css
```

Possivelmente:

```text
views/index.ejs
```

Somente se houver estilos locais da sidebar que conflitem com o comportamento responsivo global.

## Situacao atual relevante

O projeto ja usa `views/partials/sidebar.ejs` para renderizar a sidebar nas views autenticadas.

O CSS global define:

```css
.sidebar {
    width: 250px;
    position: fixed;
    height: 100vh;
}

.main-content {
    margin-left: 250px;
}
```

E abaixo de `768px`:

```css
.sidebar {
    width: 64px;
}

.sidebar-header h2,
.sidebar-nav a span,
.sidebar-footer span {
    display: none;
}

.main-content {
    margin-left: 64px;
}
```

Porem, os links do menu no partial nao envolvem os textos em `span`, entao os rotulos continuam visiveis mesmo quando a sidebar reduz para `64px`.

## Requisitos funcionais

1. Em telas largas, a sidebar deve continuar exibindo icone e texto dos links.
2. Em telas pequenas, a sidebar deve exibir apenas os icones dos links principais.
3. Em telas pequenas, os textos `Scripts`, `Agendamentos`, `Historico` e `Configuracoes` nao devem aparecer.
4. Em telas pequenas, o rodape nao deve exibir nome, email ou username do usuario.
5. Em telas pequenas, o link de logout deve manter o icone e ocultar o texto `Sair`.
6. O conteudo principal nao deve ficar por baixo dos textos ou icones da sidebar.
7. O item ativo do menu deve continuar visivel.
8. Os links do menu devem continuar navegando para as mesmas rotas.
9. O logout deve continuar apontando para `/logout`.
10. Em telas largas, a alteracao nao deve piorar o layout atual.

## Requisitos tecnicos

- Envolver os rotulos dos links da navegacao em `span`.
- Envolver o texto `Sair` em `span`.
- Usar `<%= ... %>` para dados do usuario, mantendo escape EJS.
- Manter Font Awesome como dependencia visual ja existente.
- Atualizar o bloco `@media (max-width: 768px)` em `public/styles.css`.
- Centralizar icones e botoes da sidebar no modo compacto.
- Ajustar `padding` da sidebar compacta para evitar overflow horizontal.
- Garantir que `.main-content` continue usando `margin-left: 64px` em telas pequenas.
- Evitar JavaScript para essa solucao.
- Nao alterar a semantica dos links.
- Evitar mudancas amplas no CSS global alem da sidebar responsiva.

## Sugestao de implementacao

1. Alterar os links de `views/partials/sidebar.ejs` para este formato:

```ejs
<a href="/" class="<%= currentMenu === 'scripts' ? 'active' : '' %>">
    <i class="fas fa-code"></i>
    <span>Scripts</span>
</a>
```

2. Repetir o mesmo padrao para:
   - `Agendamentos`;
   - `Historico`;
   - `Configuracoes`.
3. Alterar o logout para envolver o texto em `span`:

```ejs
<a href="/logout" class="logout-btn">
    <i class="fas fa-sign-out-alt"></i>
    <span>Sair</span>
</a>
```

4. Avaliar adicionar `title` e `aria-label` nos links para preservar identificacao quando a sidebar estiver apenas com icones.
5. Atualizar o CSS responsivo para ocultar textos e centralizar itens:

```css
@media (max-width: 768px) {
    .sidebar {
        width: 64px;
    }

    .sidebar-header h2,
    .sidebar-nav a span,
    .sidebar-footer .user-info,
    .logout-btn span {
        display: none;
    }

    .sidebar-header,
    .sidebar-nav a,
    .logout-btn {
        justify-content: center;
        padding-left: 0;
        padding-right: 0;
    }

    .sidebar-nav a i {
        width: auto;
        font-size: 1.1rem;
    }

    .sidebar-footer {
        padding: 1rem 0;
        align-items: center;
    }

    .main-content {
        margin-left: 64px;
        padding: 1rem;
    }
}
```

6. Verificar se estilos locais em `views/index.ejs` para `.sidebar-footer`, `.user-info` e `.logout-btn` nao impedem a regra global responsiva.
7. Se houver conflito, preferir ajustar a regra responsiva global com seletor mais especifico ou remover apenas a duplicacao local relacionada, sem refatorar outros estilos da pagina.

## Criterios de aceite

- Em largura maior que `768px`, a sidebar continua mostrando icones e textos.
- Em largura menor ou igual a `768px`, a sidebar mostra apenas icones nos links principais.
- Em largura menor ou igual a `768px`, o texto `Sair` nao aparece, mas o icone de logout aparece.
- Em largura menor ou igual a `768px`, dados do usuario nao aparecem no rodape.
- O conteudo principal nao fica sobreposto ao menu lateral.
- O item ativo continua destacado.
- Todos os links da sidebar continuam funcionando.
- O logout continua funcionando.
- Nenhuma dependencia nova e adicionada.
- Nenhuma rota, controller, model ou arquivo SQLite e alterado.

## Testes sugeridos

- Abrir `/` autenticado em largura desktop e confirmar que o menu permanece completo.
- Reduzir a largura para abaixo de `768px` e confirmar que a sidebar mostra apenas icones.
- Confirmar que os textos dos links nao aparecem nem sobrepoem o conteudo.
- Confirmar que o conteudo principal inicia apos a sidebar compacta.
- Confirmar que o item ativo continua destacado.
- Clicar nos icones de Scripts, Agendamentos, Historico e Configuracoes.
- Confirmar que o icone de logout permanece visivel e funcional.
- Testar em largura pequena nas telas:
  - `/`;
  - `/schedules`;
  - `/history`;
  - `/settings`.

## Validacao esperada

Como a mudanca esperada envolve EJS e CSS, validar visualmente as telas afetadas com o servidor em execucao quando possivel.

Nao e esperado alterar JavaScript. Se algum arquivo JavaScript for alterado por necessidade inesperada, rodar `node --check` no arquivo alterado.

Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.
