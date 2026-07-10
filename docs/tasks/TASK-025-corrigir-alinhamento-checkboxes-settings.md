# TASK-025 - Corrigir alinhamento de checkboxes na tela Configuracoes

## Contexto

Na tela Configuracoes (`/settings`, view `views/settings.ejs`), dois campos do tipo checkbox apresentam problema de alinhamento:

1. **Enviar resumo diario dos agendamentos** (campo `email.daily_summary_enabled`) - o texto do label fica muito distante do checkbox.
2. **Usar SSL/TLS direto** (campo `email.smtp_secure`) - mesmo problema.

## Causa raiz

No CSS inline da view (`views/settings.ejs` linha 10-150), a regra `.form-group label` define `display: block`, o que força quebra de linha e ocupa largura total. As classes `.checkbox-field` (usada nos labels dos checkboxes) e `.field-hint` (usada nas dicas) sao referenciadas no HTML mas **nao existem no CSS**, entao nao aplicam o `inline-flex` necessario para alinhar checkbox + texto na mesma linha.

## Objetivo

Corrigir o CSS para que:
- Checkbox e seu texto fiquem na mesma linha, alinhados visualmente (checkbox a esquerda, texto a direita, com espacamento confortavel).
- O label seja clicavel em toda a area (checkbox + texto) para melhor UX.
- Dicas (`.field-hint`) fiquem abaixo do campo, com fonte menor e cor secundaria.
- Manter consistencia visual com demais campos do formulario.
- Nao quebrar layout em mobile (responsivo).

## Escopo

- Apenas ajustes no CSS inline de `views/settings.ejs` (linhas 10-150).
- Nao alterar HTML/EJS, apenas adicionar/ajustar regras CSS.
- Nao mexer em `public/styles.css` nem em outras views.

## Fora de escopo

- Refatoracao completa do CSS do projeto.
- Mudar estrutura HTML dos campos.
- Alterar logica do controller ou model.

## Arquivos a alterar

```
views/settings.ejs
```

## Requisitos funcionais

1. Adicionar regra `.checkbox-field` com:
   - `display: inline-flex`
   - `align-items: center`
   - `gap: 0.5rem` (ou similar)
   - `cursor: pointer`
   - `color: var(--text-secondary)` (herdar cor do label)
   - Garantir que sobrescreva o `display: block` do `.form-group label`.

2. Adicionar regra `.field-hint` com:
   - `color: var(--text-secondary)`
   - `font-size: 0.875rem` (ou `0.8125rem`)
   - `margin-top: 0.35rem`
   - `margin-bottom: 0` (para nao criar espaco extra excessivo)

3. Ajustar seletor para que `.checkbox-field` tenha prioridade sobre `.form-group label`. Opcoes:
   - Usar `.form-group label.checkbox-field` (especificidade maior)
   - Ou `.form-group .checkbox-field` (ja que esta dentro do form-group)

4. Garantir que o checkbox em si tenha tamanho adequado (ja definido pelo browser, mas pode ajustar `width: 1rem; height: 1rem;` se necessario).

5. Testar visualmente em desktop e mobile (largura < 640px) - o checkbox nao deve quebrar layout.

## Criterios de aceite

- Ao abrir `/settings` no navegador:
  - "Enviar resumo diario dos agendamentos" aparece na mesma linha do checkbox, com espacamento padrao (~8px).
  - "Usar SSL/TLS direto" aparece na mesma linha do checkbox correspondente.
  - Clicar no texto marca/desmarca o checkbox (label funcional).
  - Dicas (ex: "Deixe em branco para manter a senha atual.") aparecem abaixo do campo, fonte menor, cor secundaria.
  - Layout nao quebra em mobile (testar redimensionando janela).
- `node --check app.js` passa (nao altera JS).
- Validacao manual visual confirmada.

## Validacao esperada

- Iniciar aplicacao: `npm start` ou `npm run dev`.
- Acessar `http://localhost:3000/settings` (com login).
- Inspecionar os dois campos checkbox mencionados.
- Confirmar alinhamento horizontal, espacamento, cor, cursor pointer.
- Redimensionar para largura mobile (< 640px) e confirmar que nao ha overflow nem quebra feia.