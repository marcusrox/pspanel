# TASK-039 - Recolher parametros opcionais no Painel de Scripts

## Contexto

Na tela principal `Painel de Scripts` (`views/index.ejs`), o quadro `Parametros` renderiza todos os campos declarados pelo script selecionado. Quando o script possui muitos parametros opcionais, esses campos aumentam significativamente a altura do quadro e afastam as acoes de execucao do restante da tela.

O cabecalho do quadro ja possui o botao com icone `?`, usado para mostrar ou ocultar as informacoes de `Parametros Necessarios`. A tela tambem ja persiste valores de parametros por usuario e script no `localStorage`, usando a chave versionada `pspanel.scriptParameters.v1`.

## Objetivo

Manter os parametros estruturados opcionais recolhidos por padrao e adicionar, ao lado do icone `?` existente, um botao com icone para mostrar ou ocultar esses campos. A preferencia deve ser lembrada por script no mesmo navegador, reduzindo o espaco vertical ocupado sem esconder os parametros obrigatorios.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

- Alterar somente a experiencia do quadro `Parametros` na tela principal `Painel de Scripts`.
- Separar visualmente os campos estruturados obrigatorios dos opcionais durante a renderizacao dinamica.
- Manter os campos obrigatorios sempre visiveis.
- Manter os campos estruturados opcionais ocultos por padrao quando ainda nao existir preferencia salva para o script.
- Adicionar um botao com icone no cabecalho do quadro, imediatamente ao lado do botao `?` existente.
- Alternar entre mostrar e ocultar os campos opcionais ao acionar o novo botao.
- Persistir a preferencia de exibicao por usuario e por script no `localStorage`.
- Restaurar a preferencia depois de trocar de script, voltar ao script anterior ou recarregar a pagina.
- Preservar os valores ja preenchidos ou restaurados quando os campos opcionais forem ocultados.
- Atualizar o controle de release ao concluir a implementacao, conforme `AGENTS.md`.

## Fora de escopo

- Alterar o parser de parametros PowerShell.
- Alterar a identificacao ou a validacao de parametros obrigatorios.
- Alterar nomes, tipos, valores padrao ou descricoes dos campos.
- Alterar o formato enviado para `POST /run-script`.
- Alterar a persistencia dos valores dos parametros, exceto pela extensao necessaria para guardar a preferencia de exibicao.
- Recolher o campo livre `Parametros adicionais` (`#params`).
- Aplicar o mesmo comportamento na tela de Agendamentos.
- Persistir a preferencia no backend ou em banco SQLite.
- Adicionar dependencia externa.

## Arquivos provaveis

```text
views/index.ejs
src/config/release.js
```

Os estilos devem permanecer localizados em `views/index.ejs`, acompanhando o padrao atual da tela, salvo se durante a implementacao surgir reutilizacao real em outras views.

## Situacao atual relevante

- O cabecalho do quadro usa `.panel-header` e contem `#parameterHelpBtn`, que chama `toggleParameterInfo()`.
- Os campos estruturados sao criados por `renderParameterFields(parameters)` dentro de `#parameterGrid`.
- Cada definicao informa se o parametro e obrigatorio por meio de `param.mandatory`.
- `clearParameterFields()` limpa os campos, a ajuda geral e os estados visuais ao trocar ou remover a selecao.
- A selecao de um script chama, nesta ordem, `renderParameterFields(...)`, `restoreSavedScriptParameters(name)` e `showScriptInfoForParams(scriptData)`.
- O estado dos valores ja usa `SCRIPT_PARAMETERS_STORAGE_KEY` e e organizado por usuario e nome do script.

## Requisitos funcionais

1. Ao selecionar pela primeira vez um script com parametros opcionais, os campos opcionais devem iniciar ocultos.
2. Os parametros obrigatorios devem permanecer visiveis e preenchiveis independentemente do estado dos opcionais.
3. O campo `Parametros adicionais` deve permanecer visivel e com o comportamento atual.
4. O novo botao deve aparecer no topo do quadro `Parametros`, imediatamente ao lado do icone `?` existente.
5. O novo botao deve ser exibido apenas quando o script selecionado possuir ao menos um parametro estruturado opcional. Quando nenhum script estiver selecionado ou quando todos os parametros forem obrigatorios, ele deve ficar oculto.
6. Ao acionar o botao quando os opcionais estiverem ocultos, todos os campos estruturados opcionais do script devem ser exibidos.
7. Ao acionar novamente o botao, os campos opcionais devem ser ocultados.
8. Ocultar campos opcionais nao deve limpar seus valores nem impedir que valores restaurados sejam enviados na execucao.
9. A preferencia deve ser independente para cada script. Mostrar os opcionais de um script nao deve alterar o estado de outro.
10. A preferencia deve ser separada por usuario quando o identificador de usuario ja disponivel na view puder ser utilizado, seguindo a estrutura atual de persistencia.
11. Ao voltar a um script selecionado anteriormente, a interface deve restaurar sua ultima preferencia salva.
12. Ao recarregar a pagina e selecionar novamente o script, a preferencia deve ser restaurada.
13. Na ausencia de preferencia salva, inclusive para scripts que ja tenham valores persistidos pelo formato anterior, deve prevalecer o estado padrao oculto.
14. Limpar o formulario ou remover a selecao deve ocultar o novo botao e retornar o estado visual sem script selecionado, sem apagar a preferencia persistida.
15. A acao existente `Limpar parametros salvos` deve continuar removendo os valores do script. A implementacao deve preservar a preferencia de exibicao ou documentar claramente sua remocao; preferencialmente, a preferencia deve ser preservada por ser uma configuracao visual distinta dos valores preenchidos.
16. Falhas ou indisponibilidade do `localStorage` devem manter a tela funcional, usando o padrao de opcionais ocultos.

## Aparencia e textos

- Usar um icone Font Awesome coerente com expandir/recolher, aproveitando a biblioteca ja carregada pela view.
- Nao usar outro icone `?`, para nao confundir a nova acao com a ajuda de parametros necessarios.
- Manter o novo botao no mesmo grupo visual e com dimensoes compativeis com `#parameterHelpBtn`.
- Atualizar `title` e `aria-label` conforme o estado:
  - `Mostrar parametros opcionais` quando os campos estiverem ocultos;
  - `Ocultar parametros opcionais` quando os campos estiverem visiveis.
- O icone pode mudar de orientacao ou estado visual para reforcar se a area esta expandida ou recolhida.
- O layout deve continuar utilizavel em desktop e em larguras mobile, sem sobrepor o titulo `Parametros` ou o botao de ajuda existente.

## Requisitos de acessibilidade

- Usar `button type="button"` para o novo controle.
- Fornecer `aria-label` e `title` em portugues, atualizados conforme o estado.
- Usar `aria-expanded="false"` quando os opcionais estiverem ocultos e `aria-expanded="true"` quando estiverem visiveis.
- Usar `aria-controls` apontando para um conteiner estavel que agrupe os campos opcionais.
- Garantir acionamento por mouse, `Enter` e `Space` pelo comportamento nativo do botao.
- Preservar indicador de foco visivel.
- Campos ocultos nao devem permanecer navegaveis por teclado nem ser anunciados como conteudo visivel por leitores de tela.
- A ordem dos controles no DOM e na navegacao por teclado deve acompanhar a ordem visual no cabecalho.

## Requisitos de persistencia

- Reaproveitar a chave `pspanel.scriptParameters.v1`, sem criar uma chave global desconectada da estrutura existente, a menos que a implementacao demonstre necessidade tecnica clara.
- Guardar a preferencia junto ao estado do usuario e do script, por exemplo com uma propriedade booleana:

```json
{
  "user:usuario": {
    "script:ScriptExemplo.ps1": {
      "values": {},
      "additionalParameters": "",
      "optionalParametersExpanded": true
    }
  }
}
```

- O nome da propriedade e ilustrativo, mas deve expressar claramente o estado salvo.
- Tratar a ausencia da propriedade como `false`.
- Aceitar somente valor booleano ao restaurar a preferencia; valores de outro tipo devem ser ignorados.
- Preservar `values` e `additionalParameters` ao atualizar apenas a preferencia visual.
- Preservar a preferencia visual ao salvar novamente os valores dos campos.
- Envolver leitura e escrita em `try/catch`, seguindo os helpers atuais.
- Nao registrar no console valores de parametros ou o conteudo completo armazenado.

## Requisitos tecnicos

- Manter a mudanca concentrada em `views/index.ejs`.
- Ajustar a renderizacao para criar um conteiner identificavel para os campos opcionais, sem alterar os atributos `name` e `id` dos inputs.
- Evitar remover campos opcionais do DOM ao recolher. Preferir oculta-los de modo que seus valores sejam preservados e continuem participando do submit atual.
- Aplicar a preferencia somente depois de identificar o script selecionado e renderizar seus campos.
- Garantir que a restauracao de valores continue ocorrendo mesmo quando os opcionais estiverem ocultos.
- Atualizar o estado visual, `aria-expanded`, `title` e `aria-label` por uma funcao unica para evitar divergencias.
- Ao selecionar outro script, nao reutilizar temporariamente o estado visual do script anterior.
- `clearParameterFields()` deve limpar o estado visual do controle sem excluir a preferencia salva.
- Manter intactos o botao `#parameterHelpBtn`, `toggleParameterInfo()` e a ajuda individual de cada campo.
- Nao adicionar bibliotecas ou alterar rotas, controllers ou services.
- Manter mensagens e rotulos visiveis em portugues.

## Sugestao de implementacao

1. Adicionar ao lado de `#parameterHelpBtn` um novo botao inicialmente oculto e com `aria-expanded="false"`.
2. Durante `renderParameterFields(parameters)`, separar os parametros por `param.mandatory` e agrupar os opcionais em um conteiner proprio com `id` estavel.
3. Manter os campos obrigatorios na area sempre visivel e esconder apenas o conteiner de opcionais.
4. Criar helpers para:
   - verificar se o script possui parametros opcionais;
   - obter a preferencia salva do script atual;
   - aplicar o estado expandido ou recolhido;
   - persistir somente a preferencia sem sobrescrever os valores existentes;
   - atualizar icone, `aria-expanded`, `title` e `aria-label`.
5. Depois de renderizar e restaurar os valores do script, aplicar sua preferencia salva. Na ausencia dela, aplicar `false`.
6. Integrar a nova propriedade aos helpers existentes de leitura, captura, persistencia e remocao para que atualizacoes de valores nao eliminem o estado visual.
7. Ajustar `clearParameterFields()` e o fluxo de limpeza para ocultar e resetar apenas o controle visual atual.
8. Atualizar `src/config/release.js` com a data/hora corrente da implementacao e incrementar o sequencial em 1.

## Criterios de aceite

- Um script com muitos parametros opcionais abre com esses campos recolhidos quando nao ha preferencia salva.
- Os parametros obrigatorios continuam sempre visiveis.
- `Parametros adicionais` continua sempre visivel.
- O novo icone aparece ao lado do `?` somente para scripts que possuem parametros opcionais.
- O clique alterna corretamente entre mostrar e ocultar todos os campos opcionais.
- O texto acessivel, o `title`, o icone e `aria-expanded` refletem o estado atual.
- Valores preenchidos em campos opcionais permanecem intactos depois de ocultar e reabrir a area.
- A execucao continua enviando campos opcionais preenchidos mesmo quando a area estiver recolhida.
- A preferencia e restaurada ao trocar de script e ao recarregar a pagina.
- Scripts diferentes mantem preferencias independentes.
- Usuarios diferentes nao compartilham a preferencia quando o identificador da view estiver disponivel.
- Estado antigo do `localStorage`, sem a nova propriedade, continua valido e resulta em opcionais ocultos.
- JSON invalido ou falha de armazenamento nao quebra selecao, preenchimento ou execucao.
- O botao de ajuda `?`, as ajudas individuais, a validacao de obrigatorios e a limpeza de valores continuam funcionando.
- O layout permanece correto em desktop e mobile.
- O release exibido pela aplicacao e atualizado quando a task for implementada.

## Testes sugeridos

- Selecionar um script com parametros obrigatorios e opcionais e confirmar que somente os obrigatorios aparecem inicialmente.
- Expandir os opcionais, preencher valores, recolher e expandir novamente, confirmando a preservacao.
- Executar o script com um opcional preenchido e recolhido, confirmando que o valor e enviado.
- Trocar entre dois scripts, deixando um expandido e outro recolhido, e confirmar a restauracao independente.
- Recarregar a pagina e confirmar a preferencia do script selecionado novamente.
- Selecionar um script com apenas parametros obrigatorios e confirmar que o novo botao nao aparece.
- Selecionar um script sem parametros declarados e confirmar que o estado vazio atual permanece correto.
- Testar um script com somente parametros opcionais e confirmar que o quadro fica compacto, mantendo `Parametros adicionais` e as acoes visiveis.
- Usar `Limpar` e confirmar que a selecao e o controle visual somem sem apagar a preferencia.
- Usar `Limpar parametros salvos` e confirmar que os valores sao removidos sem afetar indevidamente a preferencia visual.
- Corromper manualmente a nova propriedade e o JSON completo do `localStorage` em testes separados, confirmando fallback seguro.
- Navegar ate o novo botao com `Tab` e aciona-lo com `Enter` e `Space`.
- Conferir `aria-expanded`, `aria-controls`, `aria-label` e `title` nos dois estados.
- Validar o cabecalho e a grade em desktop e largura mobile.

## Validacao esperada

Validar a compilacao da view:

```powershell
node -e "const fs=require('fs'); const ejs=require('ejs'); ejs.compile(fs.readFileSync('views/index.ejs','utf8'), {filename:'views/index.ejs'}); console.log('EJS OK');"
```

Validar a sintaxe do JavaScript inline da view conforme o procedimento usado no projeto e executar:

```powershell
node --check src\config\release.js
```

Realizar validacao visual e funcional da tela principal com usuario autenticado, incluindo desktop, largura mobile, navegacao por teclado, scripts com diferentes combinacoes de parametros, troca de script e recarga da pagina.

Nao executar `npm test`, pois o projeto ainda nao possui testes reais configurados.

Se a validacao visual exigir login, usar credenciais locais apenas quando ja fornecidas ou autorizadas e nunca imprimir valores do `.env`.

---

## Assinatura da LLM

- Data: 2026-07-15 15:27:23 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 2026-07-15 15:35:47 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
