# TASK-028 - Corrigir alinhamento de checkboxes na tela Configuracoes

## Contexto

Na tela Configuracoes (`/settings`, view `views/settings.ejs`), dois campos do tipo checkbox apresentam problema de alinhamento:

1. **Enviar resumo diario dos agendamentos** (campo `email.daily_summary_enabled`) - o texto do label fica muito distante do checkbox.
2. **Usar SSL/TLS direto** (campo `email.smtp_secure`) - mesmo problema.

## Diagnostico inicial

No CSS inline da view, a regra `.form-group label` define `display: block`, o que força labels comuns a ocuparem a largura total.

As classes `.checkbox-field` e `.field-hint` ja existem no CSS atual da view, mas `.checkbox-field` usa seletor simples. Como `.form-group label` tem especificidade maior que `.checkbox-field`, a propriedade `display: block` pode vencer `display: inline-flex`, deixando checkbox e texto desalinhados ou distantes.

A correcao deve, portanto, aumentar a especificidade do seletor do checkbox, sem reescrever a tela.

## Objetivo

Corrigir o CSS para que:
- Checkbox e seu texto fiquem na mesma linha, alinhados visualmente (checkbox a esquerda, texto a direita, com espacamento confortavel).
- O label seja clicavel em toda a area (checkbox + texto) para melhor UX.
- Dicas (`.field-hint`) fiquem abaixo do campo, com fonte menor e cor secundaria.
- Manter consistencia visual com demais campos do formulario.
- Nao quebrar layout em mobile (responsivo).

## Escopo

- Apenas ajustes no CSS inline de `views/settings.ejs` (linhas 10-150).
- Nao alterar HTML/EJS, salvo se for estritamente necessario apos validacao visual.
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

1. Ajustar a regra do checkbox com seletor mais especifico, por exemplo `.form-group label.checkbox-field`, garantindo:
   - `display: inline-flex`
   - `align-items: center`
   - `gap: 0.5rem` (ou similar)
   - `cursor: pointer`
   - `color: var(--text-secondary)` (herdar cor do label)
   - prioridade sobre o `display: block` de `.form-group label`.

2. Revisar a regra `.field-hint`, que ja existe, e ajustar se necessario:
   - `color: var(--text-secondary)`
   - `font-size: 0.875rem` (ou `0.8125rem`)
   - `margin-top: 0.35rem`
   - `margin-bottom: 0` (para nao criar espaco extra excessivo)

3. Se necessario, adicionar regra para o input dentro do label, por exemplo `.form-group label.checkbox-field input[type="checkbox"]`, apenas para manter tamanho/alinhamento consistente.

4. Garantir que o checkbox em si tenha tamanho adequado (ja definido pelo browser, mas pode ajustar `width: 1rem; height: 1rem;` se a validacao visual mostrar necessidade).

5. Testar visualmente em desktop e mobile (largura < 640px) - o checkbox nao deve quebrar layout.

## Criterios de aceite

- Ao abrir `/settings` no navegador:
  - "Enviar resumo diario dos agendamentos" aparece na mesma linha do checkbox, com espacamento padrao (~8px).
  - "Usar SSL/TLS direto" aparece na mesma linha do checkbox correspondente.
  - Clicar no texto marca/desmarca o checkbox (label funcional).
  - Dicas (ex: "Deixe em branco para manter a senha atual.") aparecem abaixo do campo, fonte menor, cor secundaria.
  - Layout nao quebra em mobile (testar redimensionando janela).
- Nao ha alteracao de comportamento no backend.
- Validacao manual visual confirmada.

## Validacao esperada

- Iniciar aplicacao: `npm start` ou `npm run dev`, se for pratico e houver ambiente/login disponivel.
- Acessar `http://localhost:3000/settings` (com login).
- Inspecionar os dois campos checkbox mencionados.
- Confirmar alinhamento horizontal, espacamento, cor, cursor pointer.
- Redimensionar para largura mobile (< 640px) e confirmar que nao ha overflow nem quebra feia.
- Como a alteracao esperada e apenas EJS/CSS, `node --check app.js` e opcional como sanity check, nao validacao principal.
