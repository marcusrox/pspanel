# Task: Ajuste global do tamanho das fontes

## Contexto

O PS Panel utiliza fontes modernas e uma interface visualmente agradavel, mas em algumas telas ha bastante informacao para exibir ao mesmo tempo. Em monitores menores, notebooks ou cenarios de uso com muitas linhas em tabelas e listas, o tamanho atual das fontes pode reduzir a quantidade de informacao visivel sem rolagem.

Atualmente, os tamanhos de fonte sao definidos principalmente em CSS, com bastante uso de unidades `rem`. Isso permite aplicar um ajuste global de escala alterando o tamanho base da fonte da pagina, sem precisar editar individualmente cada titulo, botao, campo e tabela.

## Objetivo

Adicionar uma opcao geral de aparencia para permitir que o usuario diminua ou aumente o tamanho das fontes do PS Panel.

## Escopo

- Criar uma configuracao global para escala de fonte da interface.
- Adicionar uma secao de aparencia na tela de configuracoes.
- Permitir selecionar pelo menos quatro tamanhos:
  - Super Compacto;
  - Compacto;
  - Normal;
  - Grande.
- Aplicar a escala de fonte em todas as telas autenticadas do sistema.
- Persistir a preferencia no banco de configuracoes existente.
- Manter o tamanho atual como padrao para usuarios que nao alterarem a configuracao.

## Fora de escopo

- Criar temas visuais completos.
- Alterar familia de fonte.
- Alterar cores, contraste ou densidade de espacamentos de forma independente.
- Criar preferencias por usuario individual, salvo se ja houver infraestrutura simples para isso.
- Reescrever todos os tamanhos de fonte existentes manualmente.
- Ajustar layout de componentes que tenham problemas especificos nao relacionados diretamente a escala global.

## Requisitos funcionais

1. A tela de configuracoes deve exibir uma nova secao chamada `Aparencia`.
2. A secao deve permitir escolher o tamanho global das fontes.
3. A opcao padrao deve preservar o tamanho atual da interface.
4. Ao salvar a configuracao, a nova escala deve ser aplicada nas telas do sistema.
5. O usuario deve conseguir voltar ao tamanho normal pela propria tela de configuracoes.
6. O ajuste deve afetar titulos, menus, botoes, formularios, tabelas e textos auxiliares sempre que eles estiverem baseados em `rem`.
7. A configuracao deve continuar aplicada apos reiniciar o servidor.

## Requisitos tecnicos

- Adicionar uma nova chave de configuracao no model `src/models/Settings.js`, por exemplo:

```text
ui.font_scale
```

- Usar valores percentuais seguros, por exemplo:

```text
85
90
100
110
```

- A configuracao padrao deve ser `100`.
- Disponibilizar a configuracao para as views atraves de `res.locals`, preferencialmente em middleware global no `app.js`.
- Aplicar a escala no elemento raiz da pagina, por exemplo:

```html
<html lang="pt-BR" style="font-size: <%= ui?.fontScale || 100 %>%;">
```

- Validar a configuracao no controller `src/controllers/settingsController.js`.
- Aceitar apenas valores dentro de uma faixa segura, por exemplo entre `85` e `120`, ou apenas uma lista fechada de valores permitidos.
- Evitar que valores invalidos quebrem o CSS ou sejam refletidos diretamente sem validacao.
- Reaproveitar a estrutura existente de `views/settings.ejs` e `Settings.set`.

## Sugestao de implementacao

- Backend:
  - incluir `'ui.font_scale': '100'` nas configuracoes padrao de `src/models/Settings.js`;
  - criar middleware em `app.js` para carregar `ui.font_scale` e expor em `res.locals.ui`;
  - validar `ui.font_scale` em `SettingsController.updateSettings`;
  - salvar o valor junto com as demais configuracoes enviadas pelo formulario.

- Frontend:
  - adicionar uma nova secao `Aparencia` em `views/settings.ejs`;
  - usar um `select` para os tamanhos de fonte;
  - marcar como selecionado o valor salvo em `settings.ui?.font_scale`;
  - aplicar `style="font-size: ...%"` no elemento `<html>` das views principais.

Exemplo de controle na tela de configuracoes:

```html
<div class="settings-section">
    <h2>
        <i class="fas fa-font"></i>
        Aparencia
    </h2>
    <div class="form-group">
        <label for="ui.font_scale">Tamanho da fonte</label>
        <select id="ui.font_scale" name="ui.font_scale">
            <option value="85">Super Compacto</option>
            <option value="90">Compacto</option>
            <option value="100">Normal</option>
            <option value="110">Grande</option>
        </select>
    </div>
</div>
```

Exemplo de middleware:

```js
app.use(async (req, res, next) => {
  try {
    const fontScale = await Settings.get('ui.font_scale');
    res.locals.ui = {
      fontScale: fontScale || '100'
    };
    next();
  } catch (error) {
    next(error);
  }
});
```

## Criterios de aceite

- A tela de configuracoes exibe a secao `Aparencia`.
- O usuario consegue selecionar `Super Compacto`, `Compacto`, `Normal` ou `Grande`.
- Ao escolher `Super Compacto`, a interface reduz ainda mais a fonte para cenarios com alta densidade de informacao.
- A opcao selecionada e salva com sucesso.
- Ao escolher `Compacto`, a interface exibe mais informacao na tela por causa da reducao da fonte.
- Ao escolher `Grande`, a interface aumenta a legibilidade geral.
- Ao escolher `Normal`, a interface volta ao tamanho atual.
- A configuracao permanece apos reiniciar a aplicacao.
- Valores invalidos enviados manualmente nao sao aceitos.
- Nenhuma tela autenticada quebra visualmente ao aplicar as opcoes disponiveis.

## Testes sugeridos

- Acessar `/settings` autenticado e confirmar que a secao `Aparencia` aparece.
- Selecionar `Super Compacto`, salvar e confirmar que a interface fica ainda mais densa sem quebrar o layout.
- Selecionar `Compacto`, salvar e confirmar que a interface fica menor.
- Navegar para scripts, agendamentos e historico e confirmar que a escala permanece aplicada.
- Selecionar `Grande`, salvar e confirmar que a interface aumenta.
- Selecionar `Normal`, salvar e confirmar retorno ao tamanho original.
- Reiniciar o servidor e confirmar que a ultima configuracao salva continua aplicada.
- Enviar manualmente valor invalido para `ui.font_scale`, como:

```text
10
500
abc
100%;color:red
```

- Confirmar que esses valores sao rejeitados e nao alteram a interface.
