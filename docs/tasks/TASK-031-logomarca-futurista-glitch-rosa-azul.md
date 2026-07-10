# TASK-031 - Criar logomarca futurista com glitch rosa e azul na sidebar

## Contexto

A marca do PS Panel aparece no topo da sidebar, acima do menu, em `views/partials/sidebar.ejs`.

Hoje ela usa um icone de terminal Font Awesome e o texto simples `PS Panel`:

```text
<i class="fas fa-terminal"></i>
<h2>PS Panel</h2>
```

A proposta e transformar esse topo em uma logomarca mais futurista, com fonte grossa e animacao de glitch lateral em rosa e azul.

## Objetivo

Criar uma logomarca futurista para `PS Panel` no topo da sidebar, mantendo o icone de command line/terminal e usando:

- texto forte/grosso;
- icone de command line/terminal integrado a marca;
- visual ciber/futurista;
- efeitos laterais de glitch em rosa e azul;
- animacao discreta, mas perceptivel;
- boa legibilidade em fundo escuro.

## Escopo

- Alterar a marca no topo da sidebar.
- Manter o icone de command line/terminal como parte da marca.
- Manter o texto real `PS Panel` no HTML.
- Aplicar estilo futurista ao texto.
- Aplicar tratamento visual futurista ao icone, harmonizado com o texto.
- Aplicar glitch lateral rosa e azul no texto da marca.
- Usar CSS puro, preferencialmente em `public/styles.css`.
- Ajustar o markup em `views/partials/sidebar.ejs` apenas o necessario.
- Manter o link da marca apontando para `/`.
- Manter acessibilidade do link com `title` e `aria-label`.
- Manter compatibilidade com a sidebar compacta em telas pequenas.
- Atualizar `src/config/release.js` ao concluir a implementacao.

## Fora de escopo

- Criar ou usar imagem externa de logo.
- Criar SVG complexo.
- Usar canvas, WebGL ou biblioteca de animacao.
- Redesenhar toda a sidebar.
- Alterar os itens de menu.
- Alterar rotas, controllers, models ou dados.
- Mudar o nome do produto.
- Aplicar o efeito a outros titulos do sistema.

## Arquivos provaveis

```text
views/partials/sidebar.ejs
public/styles.css
src/config/release.js
```

Possivelmente tambem:

```text
views/index.ejs
```

Somente se algum estilo local da sidebar nessa view entrar em conflito. Preferir manter o ajuste no CSS global.

## Direcao visual desejada

A marca deve parecer uma palavra-logo futurista, nao apenas texto comum colorido.

Diretrizes:

- Usar o icone `fas fa-terminal`.
- Usar fonte grossa por CSS, por exemplo `font-weight: 800` ou `900`.
- Usar letras mais compactas e fortes, sem reduzir legibilidade.
- Usar `letter-spacing` normal ou levemente positivo, nunca negativo.
- Usar uma base de texto clara, como branco/cinza muito claro.
- Aplicar sombras laterais em rosa e azul para simular separacao cromatica.
- O glitch deve surgir nas laterais do texto, com pequenos deslocamentos horizontais.
- O efeito deve lembrar "Matrix/cyberpunk", mas com cores rosa e azul.
- O efeito deve ser elegante, nao poluido.

## Requisitos funcionais

1. A marca no topo da sidebar deve exibir `PS Panel`, com icone de command line.
2. O texto deve continuar sendo texto real no HTML.
3. O link da marca deve continuar navegando para `/`.
4. O efeito visual deve aparecer no estado normal ou no hover/focus, conforme melhor resultado visual.
5. A animacao deve ser sutil e nao atrapalhar a leitura.
6. Em telas menores que `768px`, a sidebar compacta deve continuar funcionando.
7. No modo compacto, a marca nao deve quebrar layout nem gerar overflow.
8. O foco via teclado no link da marca deve ser visivel.
9. O release exibido no rodape deve ser incrementado apos a implementacao.

## Requisitos de acessibilidade

- Preservar `aria-label="PS Panel"` no link da marca.
- Manter `title="PS Panel"`.
- Nao esconder o texto real usando apenas pseudo-elementos.
- Garantir contraste suficiente contra `var(--bg-darker)`.
- Respeitar `prefers-reduced-motion: reduce`.
- Se houver animacao constante, ela deve ser muito leve; preferir animacao acionada por hover/focus ou pulsos espaçados.
- O foco de teclado deve ter contorno visivel e consistente com o tema.

## Requisitos tecnicos

- Remover o estilo inline atual do link:

```html
style="text-decoration: none; color: inherit;"
```

- Criar classes especificas, por exemplo:

```text
sidebar-brand
sidebar-brand-title
```

- Para glitch, usar `data-text="PS Panel"` e pseudo-elementos:

```html
<span class="sidebar-brand-title" data-text="PS Panel">PS Panel</span>
```

- Evitar usar `<h2>` se isso dificultar pseudo-elementos, mas manter semantica razoavel; se trocar por `span`, garantir estilo equivalente.
- Nao usar dependencias externas.
- Nao usar imagens.
- Nao afetar `.sidebar-nav`.
- Nao afetar `.header-logo` das paginas.
- Nao criar estilos globais genericos demais; prefixar com `sidebar-brand`.

## Sugestao de implementacao

1. Em `views/partials/sidebar.ejs`:
   - manter o `<i class="fas fa-terminal">`, adicionando classe como `sidebar-brand-icon`;
   - trocar o link para `class="sidebar-brand"`;
   - usar elemento de texto com `class="sidebar-brand-title"` e `data-text="PS Panel"`.
2. Em `public/styles.css`:
   - mover estilos do link da sidebar para `.sidebar-brand`;
   - definir peso forte (`font-weight: 800` ou `900`);
   - aplicar visual futurista com `text-transform` opcional, se nao prejudicar a marca;
   - aplicar pseudo-elementos `::before` e `::after` com o mesmo texto;
   - usar rosa em um lado e azul no outro, por exemplo:

```text
rosa: #ff2bd6
azul: #22d3ee ou #38bdf8
```

   - criar keyframes com pequenos deslocamentos horizontais e recortes (`clip-path`) para faixas laterais;
   - limitar a animacao para nao piscar de forma agressiva;
   - adicionar `prefers-reduced-motion`.
3. Ajustar `@media (max-width: 768px)`:
   - ocultar o texto da marca como hoje ou reduzir para uma versao compacta textual;
   - garantir que nao haja overflow horizontal.
4. Atualizar `src/config/release.js`:
   - incrementar o numero sequencial atual;
   - usar data/hora atual no formato `DD/MM/YYYY HH:mm`.

## Criterios de aceite

- O icone de terminal continua aparecendo no topo da sidebar.
- O icone recebe tratamento visual compativel com a marca futurista.
- A marca `PS Panel` aparece com fonte grossa/futurista.
- O glitch lateral rosa e azul e visivel.
- O texto continua legivel.
- O link da marca continua apontando para `/`.
- O foco de teclado e visivel.
- A sidebar compacta em mobile nao quebra.
- O efeito respeita `prefers-reduced-motion`.
- O menu lateral continua com o mesmo comportamento.
- O release no rodape e incrementado apos a implementacao.

## Testes sugeridos

- Abrir `/` autenticado e conferir a marca no topo da sidebar.
- Passar o mouse sobre a marca e observar o glitch.
- Navegar por teclado ate a marca e verificar foco e efeito.
- Abrir `/history`, `/settings` e `/schedules` para confirmar consistencia da sidebar.
- Redimensionar para largura menor que `768px` e confirmar que nao ha overflow.
- Testar preferencia de reducao de movimento quando possivel.

## Validacao esperada

Validar compilacao do partial:

```powershell
node -e "const fs=require('fs'); const ejs=require('ejs'); ejs.compile(fs.readFileSync('views/partials/sidebar.ejs','utf8'), {filename:'views/partials/sidebar.ejs'}); console.log('EJS OK');"
```

Validar release:

```powershell
node --check src\config\release.js
```

Validar visualmente no navegador quando possivel.

Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.

---

## Assinatura da LLM

- Data: 2026-07-10
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
