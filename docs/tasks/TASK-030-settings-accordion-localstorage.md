# TASK-030 - Organizar Configuracoes em accordion com persistencia local

## Contexto

A tela de Configuracoes (`/settings`, view `views/settings.ejs`) possui atualmente tres secoes principais:

- Execucao
- Aparencia
- Email - Resumo diario

Como a tendencia e a quantidade de configuracoes crescer, a tela pode ficar longa e mais dificil de navegar. Uma forma simples de melhorar a visualizacao, sem mudar a URL nem o backend, e transformar cada secao em um accordion expansivel/recolhivel.

## Objetivo

Implementar accordion nas secoes da tela `/settings`, permitindo expandir e recolher cada grupo de configuracoes, com persistencia do estado no `localStorage`.

Ao voltar para a tela, o usuario deve encontrar as secoes no mesmo estado em que deixou na ultima visita.

## Escopo

- Alterar apenas a experiencia visual da tela `/settings`.
- Transformar as secoes `.settings-section` existentes em blocos expansíveis.
- Persistir o estado aberto/fechado de cada secao no `localStorage`.
- Manter os campos, nomes, valores, validacoes e submit atuais.
- Manter os botoes `Restaurar`, `Salvar Alteracoes` e `Enviar resumo agora` funcionando como hoje.
- Manter textos visiveis em portugues.
- Manter implementacao localizada em `views/settings.ejs`, salvo pequeno ajuste em `public/styles.css` se ficar claramente reutilizavel.
- Atualizar o controle de release ao concluir a implementacao, conforme `AGENTS.md`.

## Fora de escopo

- Criar novas configuracoes.
- Alterar model, controller, rotas ou persistencia de configuracoes.
- Criar paginas separadas para cada categoria.
- Criar busca/filtro de configuracoes.
- Refatorar toda a tela de Configuracoes.
- Criar um sistema global de accordion para o projeto inteiro.
- Alterar layout da sidebar ou rodape.

## Arquivos provaveis

```text
views/settings.ejs
src/config/release.js
```

Possivelmente tambem:

```text
public/styles.css
```

Somente se houver estilo que faca sentido fora da tela de Configuracoes. Caso contrario, manter CSS local na propria view, seguindo o padrao atual.

## Situacao atual relevante

Em `views/settings.ejs`, as secoes usam este padrao:

```text
<div class="settings-section">
    <h2>
        <i class="..."></i>
        Nome da secao
    </h2>
    ...
</div>
```

Secoes atuais:

```text
Execucao
Aparencia
Email - Resumo diario
```

O formulario principal envolve as tres secoes:

```text
<form action="/settings/update" method="POST">
    ...
</form>
```

Existe tambem um formulario separado para envio manual do resumo diario:

```text
<form id="send-daily-summary-form" action="/settings/daily-summary/send-now" method="POST"></form>
```

Esse comportamento deve ser preservado.

## Requisitos funcionais

1. Cada secao de configuracao deve ter um cabecalho clicavel.
2. O cabecalho deve expandir/recolher apenas a propria secao.
3. O conteudo dos campos deve ficar oculto quando a secao estiver recolhida.
4. O usuario deve conseguir manter mais de uma secao aberta ao mesmo tempo.
5. O estado aberto/fechado deve ser salvo em `localStorage`.
6. Ao carregar `/settings`, a tela deve restaurar o estado salvo no navegador.
7. Se nao houver estado salvo, usar um estado inicial amigavel:
   - `Execucao` aberta;
   - `Aparencia` aberta;
   - `Email - Resumo diario` fechada, por ser a secao maior.
8. Deve existir indicacao visual de estado, por exemplo icone de chevron apontando para baixo/direita.
9. A interacao deve funcionar por clique e por teclado.
10. Os campos dentro das secoes recolhidas devem continuar sendo enviados normalmente no submit do formulario.
11. O botao `Enviar resumo agora` deve continuar funcionando.
12. Mensagens de sucesso/erro devem continuar aparecendo acima do formulario.
13. O rodape `partials/app-footer` deve continuar no final da pagina.

## Requisitos de acessibilidade

- Usar `button type="button"` no cabecalho clicavel, em vez de apenas `div` com `onclick`.
- Cada botao de secao deve ter `aria-expanded`.
- Cada conteudo de secao deve ter `id` estavel e `aria-labelledby` quando aplicavel.
- O conteudo recolhido deve usar `hidden` ou classe equivalente que remova visualmente a secao.
- Nao usar links (`<a>`) para a acao de expandir/recolher.
- O foco de teclado deve ser visivel.

## Requisitos tecnicos

- Preferir uma chave unica de `localStorage`, por exemplo:

```js
pspanel.settings.accordion
```

- Armazenar estado como JSON simples, por exemplo:

```json
{
  "execution": true,
  "appearance": true,
  "emailDailySummary": false
}
```

- Tratar JSON invalido no `localStorage` sem quebrar a tela.
- Nao depender de bibliotecas externas.
- Nao alterar nomes dos campos (`name`) nem IDs usados pelos labels.
- Nao desabilitar inputs de secoes fechadas, pois campos desabilitados nao seriam enviados no submit.
- Usar classes e atributos previsiveis, por exemplo:

```text
settings-accordion-toggle
settings-accordion-content
is-collapsed
```

- Manter a implementacao JS pequena e inline na view, como ja ocorre em outras telas.

## Sugestao de implementacao

1. Ajustar o HTML de cada `.settings-section`:
   - adicionar um identificador de secao, por exemplo `data-section-key="execution"`;
   - trocar o `h2` atual por um `h2` contendo um `button type="button"`;
   - mover os campos da secao para um container de conteudo, por exemplo `.settings-accordion-content`.
2. Adicionar CSS local para:
   - cabecalho clicavel;
   - chevron;
   - estado hover/focus;
   - conteudo recolhido;
   - responsividade.
3. Adicionar script ao final da view para:
   - carregar estado salvo;
   - aplicar estados iniciais;
   - alternar secao ao clicar;
   - atualizar `aria-expanded`;
   - persistir estado no `localStorage`.
4. Garantir que os campos dentro das secoes continuam dentro do formulario principal.
5. Atualizar `src/config/release.js`:
   - incrementar o sequencial do release atual;
   - usar data/hora atual do ambiente no formato `DD/MM/YYYY HH:mm`.

## Criterios de aceite

- `/settings` exibe as tres secoes como accordions.
- Clicar em `Execucao` expande/recolhe apenas a secao de execucao.
- Clicar em `Aparencia` expande/recolhe apenas a secao de aparencia.
- Clicar em `Email - Resumo diario` expande/recolhe apenas a secao de email.
- O estado aberto/fechado permanece apos recarregar a pagina.
- O estado salvo e independente para cada secao.
- A tela funciona mesmo se o `localStorage` estiver vazio.
- A tela nao quebra se o valor salvo no `localStorage` for JSON invalido.
- Salvar configuracoes continua enviando todos os campos.
- `Enviar resumo agora` continua usando o formulario existente.
- Layout mobile nao apresenta sobreposicao ou textos cortados no cabecalho das secoes.
- O release no rodape reflete a nova versao apos a implementacao.

## Testes sugeridos

- Abrir `/settings` autenticado.
- Confirmar estado inicial das secoes sem `localStorage` salvo.
- Expandir/recolher cada secao individualmente.
- Recarregar a pagina e confirmar que o estado foi preservado.
- Fechar todas as secoes, recarregar e confirmar persistencia.
- Alterar uma configuracao em secao aberta e salvar.
- Alterar uma configuracao em secao que foi aberta depois de estar fechada e salvar.
- Usar `Tab` e `Enter`/`Space` nos botoes de secao.
- Testar largura mobile e confirmar que os cabecalhos continuam usaveis.
- Confirmar visualmente que o rodape continua no fim da tela.

## Validacao esperada

Rodar:

```powershell
node --check src\config\release.js
```

Como a mudanca principal e EJS/CSS/JS inline, validar tambem compilacao da view:

```powershell
node -e "const fs=require('fs'); const ejs=require('ejs'); ejs.compile(fs.readFileSync('views/settings.ejs','utf8'), {filename:'views/settings.ejs'}); console.log('EJS OK');"
```

Validar visualmente `/settings` com o servidor em execucao quando possivel.

Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.

---

## Assinatura da LLM

- Data: 2026-07-10
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
