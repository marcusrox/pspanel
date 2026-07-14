# TASK-037 - Preservar parametros do painel e exibir ajuda por campo

## Contexto

Na tela principal `Painel de Scripts` (`views/index.ejs`), os campos estruturados de parametros sao montados dinamicamente depois que o usuario seleciona um script.

Atualmente, os valores digitados nesses campos e no campo de parametros adicionais sao perdidos ao recarregar a pagina, trocar de script ou retornar ao painel. Isso obriga o usuario a preencher novamente os mesmos dados antes de uma execucao posterior.

A descricao de cada parametro tambem e usada principalmente como `placeholder` do campo. O texto desaparece durante a digitacao e, em campos baseados em `ValidateSet`, aparece como opcao vazia. A descricao deve continuar nesse local e passar a ficar disponivel tambem em uma ajuda que possa ser consultada a qualquer momento.

## Objetivo

Melhorar a experiencia de execucao manual no Painel de Scripts com:

- preservacao local, por script, dos parametros informados pelo usuario;
- restauracao desses valores em acessos e execucoes posteriores no mesmo navegador;
- exibicao da descricao de cada parametro ao clicar em um icone `?` ao lado de seu nome.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

- Alterar a experiencia da tela principal `Painel de Scripts`.
- Persistir no `localStorage` os valores dos campos estruturados de parametros.
- Persistir tambem o campo de parametros adicionais, associado ao script selecionado.
- Manter um conjunto independente de valores para cada script.
- Restaurar os valores salvos quando o respectivo script for selecionado novamente.
- Adicionar uma acao visivel para apagar os parametros salvos do script selecionado.
- Adicionar um botao de ajuda `?` ao lado do nome de cada parametro que possua descricao.
- Exibir a descricao em um pequeno tooltip/popover controlado por clique.
- Manter a descricao atual no `placeholder` e apresenta-la tambem na ajuda individual do parametro.
- Preservar validacao, montagem de argumentos e execucao atuais.
- Atualizar o controle de release ao concluir a implementacao, conforme `AGENTS.md`.

## Fora de escopo

- Persistir parametros no backend ou em banco SQLite.
- Sincronizar parametros entre navegadores, computadores ou perfis diferentes.
- Compartilhar parametros salvos entre usuarios.
- Alterar o parser do bloco `param(...)` dos scripts PowerShell.
- Alterar a validacao de parametros obrigatorios.
- Alterar rotas, historico ou processo de execucao dos scripts.
- Alterar a tela de criacao/edicao de Agendamentos.
- Criar uma biblioteca global de tooltip para toda a aplicacao.

## Arquivos provaveis

```text
views/index.ejs
src/config/release.js
```

Possivelmente tambem:

```text
public/styles.css
```

Usar `public/styles.css` somente se os estilos forem claramente reutilizaveis. Caso contrario, manter o CSS localizado em `views/index.ejs`, seguindo o padrao atual da tela.

## Situacao atual relevante

Os campos sao criados dinamicamente pela funcao responsavel por renderizar parametros em `views/index.ejs`. O nome e exibido em um `label`, e a descricao e aplicada atualmente desta forma:

```text
input de texto: placeholder = descricao do parametro
select/ValidateSet: texto da opcao vazia = descricao do parametro
```

Os campos estruturados usam nomes no formato:

```text
paramValues[NomeDoParametro]
```

O campo livre `#params` aceita parametros adicionais. A persistencia deve contemplar os dois tipos de entrada sem alterar o formato enviado ao backend.

## Requisitos funcionais - persistencia

1. Cada script deve possuir seu proprio conjunto de valores salvos.
2. Ao digitar ou selecionar um valor, o estado do script deve ser atualizado no `localStorage`.
3. O salvamento deve abranger:
   - valores dos campos estruturados em `paramValues[...]`;
   - valor do campo de parametros adicionais `#params`.
4. Ao selecionar novamente um script, os valores salvos para ele devem ser restaurados nos campos correspondentes.
5. Ao recarregar a pagina e selecionar o mesmo script, os valores devem ser restaurados.
6. Trocar de script nao deve copiar valores de um script para outro.
7. Parametros novos ou removidos da assinatura de um script nao devem quebrar a restauracao:
   - chaves desconhecidas devem ser ignoradas;
   - campos novos devem iniciar vazios ou com o comportamento padrao atual.
8. Deve existir uma acao `Limpar parametros salvos` para o script selecionado.
9. Ao confirmar essa acao, os campos visiveis devem ser limpos e a entrada correspondente deve ser removida do `localStorage`.
10. A limpeza deve afetar apenas o script selecionado.
11. A tela deve continuar funcionando normalmente quando o `localStorage` estiver indisponivel, cheio ou contiver JSON invalido.
12. Falhas de leitura ou escrita local nao devem impedir a selecao nem a execucao do script.
13. O reset geral existente na tela deve manter sua finalidade atual. A implementacao deve definir explicitamente se ele apenas limpa a interface ou tambem remove os valores persistidos; a remocao definitiva deve ocorrer pela acao dedicada e claramente identificada.

## Requisitos funcionais - ajuda por parametro

1. Parametros que possuam `description` devem exibir um botao com icone `?` ao lado do nome.
2. O botao deve ser separado do `label` para que clicar na ajuda nao altere inadvertidamente o foco ou o valor do campo.
3. Ao clicar no icone, a descricao completa deve aparecer junto ao campo correspondente.
4. Um novo clique no mesmo icone deve ocultar a descricao.
5. Ao abrir a ajuda de outro parametro, a interface pode fechar a ajuda anterior para evitar sobreposicoes.
6. Pressionar `Escape` deve fechar a ajuda aberta e devolver o foco ao botao que a abriu.
7. Parametros sem descricao nao devem exibir o botao `?`.
8. A descricao deve continuar sendo usada como `placeholder` do input e deve aparecer tambem na ajuda acionada pelo icone `?`.
9. Quando nao houver descricao, inputs de texto devem manter o fallback atual baseado no valor padrao ou no nome do parametro.
10. Campos `select` devem continuar usando a descricao na opcao vazia; quando nao houver descricao, devem usar o fallback atual.
11. Tipo, valor padrao e indicador `Obrigatorio` existentes devem continuar visiveis e funcionando.
12. Ao trocar de script ou limpar os campos, qualquer ajuda aberta deve ser fechada.

## Requisitos de acessibilidade

- Usar `button type="button"` para cada icone de ajuda.
- Fornecer `aria-label` contextual, por exemplo `Exibir descricao do parametro Ambiente`.
- Usar `aria-expanded` e `aria-controls` para relacionar o botao ao conteudo da descricao.
- A descricao deve possuir `id` unico e previsivel.
- O botao deve funcionar por mouse, `Enter` e `Space`.
- O foco de teclado deve ser claramente visivel.
- Nao depender apenas do atributo `title` nem apenas de hover para apresentar a ajuda.
- O conteudo oculto nao deve ser anunciado por leitores de tela.
- O icone nao deve encobrir o nome, o selo de obrigatoriedade ou o campo em telas pequenas.

## Requisitos de seguranca e privacidade

- Por decisao funcional desta task, persistir todos os valores informados, inclusive senhas, tokens, credenciais, chaves de API, parametros `SecureString`, parametros `PSCredential` e outros dados sensiveis.
- Aplicar a mesma regra ao campo livre de parametros adicionais `#params`.
- Nao filtrar valores por nome ou tipo antes de grava-los.
- Disponibilizar a acao de limpeza dos dados salvos de forma visivel, inclusive para remocao de credenciais persistidas.
- Nao imprimir os valores persistidos em logs do navegador ou do servidor.
- Evitar inserir a descricao do parametro com `innerHTML`; usar `textContent` ou criacao segura de elementos.

## Requisitos tecnicos

- Preferir uma unica chave versionada de `localStorage`, por exemplo:

```text
pspanel.scriptParameters.v1
```

- Armazenar JSON simples organizado por usuario e nome do script, sem incluir caminho de arquivo.
- Validar a estrutura lida antes de usa-la.
- Envolver operacoes de `localStorage` em `try/catch`.
- Salvar apenas strings necessarias para recompor os campos.
- Usar eventos `input` para campos de texto e `change` para campos `select`.
- Evitar gravacao excessiva a cada tecla usando debounce curto, se necessario.
- Restaurar valores somente depois que os campos dinamicos do script forem criados.
- Nao alterar os atributos `name` usados no submit do formulario.
- Nao adicionar dependencias externas.
- Manter o JavaScript pequeno e localizado na view, salvo se a implementacao justificar um modulo reutilizavel.
- Manter mensagens visiveis ao usuario em portugues.

## Sugestao de estrutura do estado

```json
{
  "usuario": {
    "ScriptExemplo.ps1": {
      "values": {
        "Ambiente": "PROD",
        "Servidor": "srv01"
      },
      "additionalParameters": "-Verbose"
    }
  }
}
```

Os nomes sao apenas ilustrativos. A implementacao deve normalizar as chaves sem reduzir a separacao entre usuarios e scripts.

## Sugestao de implementacao

1. Criar helpers locais para:
   - ler e validar o estado persistido;
   - obter a chave do usuario e do script atual;
   - capturar e salvar todos os valores, sem excluir campos sensiveis;
   - restaurar valores nos campos renderizados;
   - remover apenas o estado do script selecionado.
2. Depois de renderizar os campos de um script, aplicar os valores salvos correspondentes.
3. Registrar listeners nos campos dinamicos e no campo adicional.
4. Adicionar o botao `Limpar parametros salvos` proximo das acoes do formulario, desabilitado quando nenhum script estiver selecionado ou nao houver estado salvo.
5. Ao montar cada `label`, adicionar um botao `?` somente quando `param.description` estiver preenchido.
6. Criar o conteudo de ajuda com texto escapado, identificador unico e estado inicial oculto.
7. Implementar abertura, fechamento e controle de foco da ajuda.
8. Preservar a descricao nos placeholders atuais e reutilizar o mesmo texto na ajuda individual.
9. Atualizar `src/config/release.js` com data/hora atual e incremento sequencial ao concluir a implementacao.

## Criterios de aceite

- Preencher parametros de um script, selecionar outro e voltar ao primeiro restaura todos os valores.
- Recarregar o painel e selecionar o script restaura todos os valores.
- Valores de scripts diferentes permanecem isolados.
- Valores de usuarios diferentes nao sao misturados quando houver identificador de usuario disponivel na view.
- A acao de limpeza remove somente os dados do script selecionado.
- JSON invalido ou indisponibilidade do `localStorage` nao quebra o painel.
- Senhas, tokens, credenciais, chaves de API, `SecureString`, `PSCredential` e demais parametros sensiveis reaparecem apos recarregar ou selecionar novamente o script.
- O campo de parametros adicionais e restaurado mesmo quando contiver valores sensiveis.
- A interface informa que os valores, inclusive dados sensiveis, ficam armazenados neste navegador.
- Nenhum valor de parametro e escrito em logs novos.
- Cada parametro com descricao exibe um icone `?` ao lado do nome.
- O clique no icone mostra e oculta a descricao correta.
- A ajuda funciona por teclado e fecha com `Escape`.
- Parametros sem descricao nao exibem icone vazio ou espaco desnecessario.
- A descricao continua sendo usada como placeholder e tambem aparece na ajuda individual.
- Inputs, selects, obrigatoriedade, parametros adicionais e botao de execucao continuam com o comportamento atual.
- O layout permanece utilizavel em desktop e mobile.
- O release exibido pela aplicacao e atualizado quando a task for implementada.

## Testes sugeridos

- Abrir o painel autenticado e selecionar um script com dois ou mais parametros.
- Preencher input de texto e `select`, trocar de script e retornar.
- Recarregar a pagina e confirmar a restauracao.
- Confirmar que outro script nao recebe os valores anteriores.
- Alterar manualmente o JSON salvo para um valor invalido e confirmar que a tela continua funcionando.
- Simular falha de `localStorage` e confirmar que a execucao continua disponivel.
- Usar `Limpar parametros salvos` e confirmar que os valores nao retornam apos recarregar.
- Testar senha, token, chave de API, `SecureString`, `PSCredential` ou outro parametro sensivel e confirmar que o valor e persistido e restaurado.
- Informar dados sensiveis nos parametros adicionais e confirmar que o conteudo completo e persistido e restaurado.
- Abrir e fechar a ajuda de cada parametro por clique.
- Navegar ate os botoes de ajuda com `Tab` e aciona-los com `Enter` e `Space`.
- Fechar uma ajuda com `Escape` e confirmar o retorno do foco.
- Confirmar que descricoes longas quebram linha sem sair do painel em largura mobile.
- Executar um script com valores restaurados e confirmar que os argumentos enviados permanecem corretos.

## Validacao esperada

Validar a compilacao da view:

```powershell
node -e "const fs=require('fs'); const ejs=require('ejs'); ejs.compile(fs.readFileSync('views/index.ejs','utf8'), {filename:'views/index.ejs'}); console.log('EJS OK');"
```

Validar a sintaxe do JavaScript inline da view conforme o procedimento usado no projeto e rodar:

```powershell
node --check src\config\release.js
```

Realizar validacao visual e funcional da tela principal com usuario autenticado, incluindo desktop, largura mobile, navegacao por teclado, troca de scripts, recarga da pagina e limpeza dos dados salvos.

Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.

Se a validacao visual exigir login, usar credenciais locais apenas quando ja fornecidas ou autorizadas e nunca imprimir valores do `.env`.

---

## Assinatura da LLM

- Data: 2026-07-14
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 2026-07-14
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
