# TASK-052 - Indicar ambiente nao produtivo na interface

## Contexto

O PS Panel pode ser executado em ambientes de desenvolvimento, teste e
producao, mas a interface atual nao apresenta um indicador visual persistente
que permita ao usuario distinguir esses ambientes.

Essa ausencia pode causar confusao durante demonstracoes, validacoes e capturas
de tela, especialmente quando o ambiente de desenvolvimento utiliza dados ou
uma aparencia semelhantes aos de producao.

Foram consideradas duas alternativas:

1. exibir a palavra `Desenvolvimento` repetida ou em diagonal no fundo das
   paginas, com baixo contraste;
2. exibir um selo proximo a identidade visual da aplicacao.

O cabecalho superior e o logo da Desenbahia nao aparecem de forma uniforme em
todas as views. Em contrapartida, as paginas autenticadas usam o partial
compartilhado `views/partials/sidebar.ejs`, que contem a identidade do PS Panel.
A tela de login possui uma identidade equivalente, mas independente.

## Objetivo

Exibir um selo visual claro e persistente junto a identidade do PS Panel quando
a aplicacao estiver em um ambiente diferente de producao.

O indicador deve:

- aparecer no topo da sidebar em todas as paginas autenticadas;
- aparecer tambem na tela de login;
- ser reforcado por uma marca d'agua horizontal no topo das paginas;
- adaptar-se ao modo compacto da sidebar em telas menores;
- usar texto, e nao apenas cor, para identificar o ambiente;
- permanecer completamente ausente em producao.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Decisao visual

Adotar um selo compacto no formato de `pill`, associado ao nome `PS Panel`.

Apresentacao sugerida para desenvolvimento:

```text
PS Panel  [DESENVOLVIMENTO]
```

Caracteristicas esperadas:

- fundo ambar discreto e semitransparente;
- texto ambar claro com contraste suficiente em relacao ao fundo do selo;
- borda sutil;
- tipografia pequena, em caixa alta e com peso intermediario;
- sem animacao;
- sem alterar a animacao ou o estilo atual da marca `PS Panel`;
- sem competir visualmente com alertas de erro ou acoes principais.

O selo deve ser tratado como informacao de contexto operacional, nao como
mensagem de erro.

### Marca d'agua horizontal no topo

Exibir adicionalmente o nome controlado do ambiente em letras grandes,
centralizado horizontalmente no topo da viewport.

A marca d'agua deve:

- usar o mesmo `environmentIndicator.label` recebido pelo selo;
- permanecer atras do conteudo e dos paineis;
- permanecer fora da area ocupada pela sidebar nas paginas autenticadas;
- nao usar rotacao ou inclinacao no texto;
- possuir baixo contraste em relacao ao fundo;
- usar o mesmo cinza-azulado neutro empregado nos textos secundarios da
  interface, sem influencia vermelha ou brilho;
- ser recortada pela viewport sem criar barra de rolagem;
- ignorar eventos de ponteiro e selecao de texto;
- ser ocultada de tecnologias assistivas com `aria-hidden="true"`;
- adaptar o tamanho da tipografia em viewports compactas;
- permanecer completamente ausente em producao.

Usar uma unica inscricao central por viewport. Nao repetir o texto em padrao
nem aplicar animacao.

### Comportamento responsivo

Em larguras acima de `768px`, exibir o nome completo do ambiente.

No modo compacto da sidebar, em que o titulo `PS Panel` e ocultado, preservar um
marcador textual reduzido, por exemplo:

```text
DEV
```

O marcador compacto deve possuir `title` ou alternativa acessivel com o nome
completo do ambiente. Ele nao deve desaparecer junto com
`.sidebar-brand-title`.

Na tela de login, o selo pode ser exibido abaixo do titulo `PS Panel`, antes do
texto `Faca login para continuar`.

## Regra de ambiente

Usar exclusivamente `process.env.NODE_ENV` no servidor para determinar o
indicador. A view nao deve ler `process.env` diretamente nem receber o objeto
completo de variaveis de ambiente.

Mapeamento esperado:

| `NODE_ENV` | Rotulo completo | Rotulo compacto | Exibir |
| --- | --- | --- | --- |
| `production` | — | — | Nao |
| `development` | `DESENVOLVIMENTO` | `DEV` | Sim |
| `test` | `TESTE` | `TESTE` | Sim |
| ausente ou outro valor | `AMBIENTE NAO PRODUTIVO` | `NAO PROD.` | Sim |

O comportamento para valor ausente ou desconhecido deve ser conservador. Como
o bootstrap atual considera producao somente quando
`NODE_ENV === 'production'`, qualquer outro valor deve continuar visivelmente
identificado como nao produtivo.

Nao exibir na interface o valor bruto de uma configuracao desconhecida. Isso
evita apresentar texto inesperado e mantem um conjunto controlado de rotulos.

## Disponibilizacao para as views

O `app.js` deve disponibilizar globalmente um objeto pequeno e seguro em
`res.locals`, por exemplo:

```js
{
    visible: true,
    label: 'DESENVOLVIMENTO',
    compactLabel: 'DEV'
}
```

O nome definitivo da propriedade pode seguir o estilo do bootstrap, desde que:

- esteja disponivel tanto para views publicas quanto autenticadas;
- nao contenha segredos ou o objeto `process.env`;
- use apenas os rotulos controlados definidos nesta task;
- permita que as views decidam somente a apresentacao, sem repetir a regra de
  ambiente;
- mantenha producao com `visible: false`.

Preferir uma funcao pequena e deterministica para montar o objeto, facilitando
a validacao dos diferentes valores de `NODE_ENV`.

## Pontos de exibicao

### Paginas autenticadas

Adicionar o indicador a `views/partials/sidebar.ejs`, junto ao bloco
`.sidebar-brand`. Dessa forma, todas as views que ja reutilizam o partial
recebem o aviso sem duplicacao.

O link da marca deve continuar levando para `/`, com foco visivel e rotulo
acessivel. O selo nao precisa ser um link independente.

### Login

Adicionar o mesmo indicador em `views/login.ejs`, junto a `.login-header`.

O aviso deve aparecer antes que o usuario se autentique, pois reconhecer o
ambiente antes do login faz parte do objetivo operacional.

### Outras views

Views auxiliares que nao representam uma pagina principal, como popups de
codigo-fonte e a pagina generica de erro, nao precisam receber um selo
duplicado nesta primeira versao.

Se uma view autenticada principal nao utilizar o partial da sidebar, ela deve
ser identificada durante a implementacao e avaliada individualmente. Nao
duplicar o indicador em todos os `.top-header` sem necessidade.

## Acessibilidade

- O ambiente deve ser compreensivel por texto; a cor ambar e apenas reforco.
- Usar saida escapada do EJS com `<%= ... %>` para os rotulos.
- Manter contraste legivel no tema escuro, inclusive com escala de fonte
  configuravel.
- O selo nao deve receber foco se nao possuir acao.
- O rotulo compacto deve fornecer o nome completo para tecnologias assistivas.
- Nao usar texto piscante, animacao ou mudanca continua de cor.
- Nao depender de pseudo-elemento CSS como unica fonte do texto.

## Arquivos provaveis

```text
app.js
views/partials/sidebar.ejs
views/login.ejs
public/styles.css
src/config/release.js
```

`src/config/release.js` deve ser alterado somente quando esta task for
implementada, incrementando o sequencial global com a data local da conclusao
no formato `vAAAA.MM.DD-NNN`, conforme `AGENTS.md`.

Nao ha necessidade prevista de criar rota, controller, model, service, partial
adicional, dependencia NPM ou configuracao persistida no SQLite.

## Fora de escopo

- Alterar o background global da aplicacao.
- Padronizar ou reescrever todos os cabecalhos das views.
- Adicionar o logo da Desenbahia a paginas que hoje nao o exibem.
- Exibir simultaneamente o selo na sidebar e ao lado do logo em cada pagina.
- Permitir que o usuario esconda o indicador.
- Tornar o ambiente configuravel por Settings ou pelo banco SQLite.
- Criar uma nova variavel de ambiente apenas para o selo.
- Exibir hostname, porta, caminho, credenciais ou outras informacoes do
  servidor.
- Alterar o comportamento de autenticacao, login automatico local ou sessao.
- Alterar `.env`, `.env.example`, dependencias ou `package-lock.json`.

A marca d'agua nao substitui o selo textual e nao deve ser usada como unica
forma de identificar o ambiente.

## Riscos e cuidados

- Verificar apenas se `NODE_ENV` e diferente de `development` pode ocultar o
  aviso em ambientes de teste ou configuracoes desconhecidas.
- Espalhar a regra entre varias views pode produzir rotulos divergentes; a
  decisao deve permanecer no servidor.
- Colocar o selo somente ao lado do logo da Desenbahia deixaria paginas sem
  indicador, pois nem todos os cabecalhos exibem esse logo.
- Ocultar todo o conteudo adicional da marca no media query de `768px` pode
  remover o aviso em dispositivos estreitos; o marcador compacto precisa de
  regra propria.
- Contraste baixo demais transforma o aviso em decoracao e deixa de cumprir o
  objetivo operacional.
- O selo nao pode alterar o `z-index`, capturar cliques ou sobrepor controles
  da sidebar.
- A marca d'agua nao pode ficar acima de paineis, formularios ou controles.
- A marca d'agua deve ser visivel no fundo sem reduzir a legibilidade do
  conteudo.
- O elemento fixo nao pode criar barras de rolagem nem ampliar a area util da
  pagina.
- A interface de producao nao deve reservar espaco vazio para um indicador
  oculto.

## Criterios de aceite

- Com `NODE_ENV=development`, todas as paginas autenticadas que usam a sidebar
  exibem `DESENVOLVIMENTO` junto a identidade do PS Panel.
- Com `NODE_ENV=development`, a tela de login tambem exibe
  `DESENVOLVIMENTO`.
- Em uma viewport de ate `768px`, a sidebar compacta continua exibindo `DEV`.
- O marcador compacto possui uma descricao acessivel com o nome completo do
  ambiente.
- Com `NODE_ENV=test`, o indicador mostra `TESTE`.
- Com `NODE_ENV` ausente ou desconhecido, o indicador mostra
  `AMBIENTE NAO PRODUTIVO`, sem apresentar o valor bruto recebido.
- Com `NODE_ENV=production`, nenhum selo, marcador ou espaco reservado e
  renderizado.
- A regra de mapeamento do ambiente existe em um unico ponto no servidor.
- As views recebem somente rotulos controlados e nao acessam o objeto
  `process.env`.
- Os rotulos dinamicos usam saida escapada do EJS.
- O indicador e compreensivel sem depender apenas da cor.
- O selo nao possui animacao e nao interfere na marca, navegacao, login ou
  controles da sidebar.
- O nome do ambiente aparece tambem como uma unica marca d'agua horizontal em
  letras grandes no topo das paginas autenticadas e do login.
- Nas paginas autenticadas, a marca d'agua comeca depois da sidebar, inclusive
  no modo compacto, e nao ocupa a area do menu lateral.
- A marca d'agua usa baixo contraste e tom cinza-azulado neutro, nao captura
  cliques, nao pode ser selecionada e permanece atras do conteudo.
- A marca d'agua e marcada com `aria-hidden="true"`.
- A marca d'agua nao cria barras de rolagem em desktop ou viewport compacta.
- Em producao, nenhum selo, marcador, marca d'agua ou espaco reservado e
  renderizado.
- Nenhuma rota, autenticacao, sessao, configuracao sensivel, dependencia ou
  dado SQLite e alterado.
- O identificador de release e incrementado quando a task for implementada.

## Testes sugeridos

1. Executar `node --check app.js`.
2. Iniciar uma instancia temporaria com `PORT=3100`,
   `NODE_ENV=development` e, quando necessario para paginas autenticadas,
   `DEV_AUTO_LOGIN_LOCAL=true`.
3. Abrir a tela de login e confirmar a presenca, legibilidade e alinhamento do
   selo completo.
4. Abrir as telas principais de Scripts, Agendamentos, Historico, Logs,
   Configuracoes e Ambiente e confirmar que o indicador aparece uma unica vez
   pela sidebar.
5. Reduzir a viewport para ate `768px` e confirmar que o titulo completo some,
   mas o marcador `DEV` permanece visivel sem sobrepor o icone da marca.
6. Aumentar a escala de fonte pelas configuracoes existentes e confirmar que o
   selo nao corta o texto nem desloca a navegacao.
7. Repetir a inicializacao temporaria com `NODE_ENV=test` e confirmar `TESTE`.
8. Repetir com `NODE_ENV` ausente ou com valor controlado desconhecido e
   confirmar `AMBIENTE NAO PRODUTIVO`, sem refletir o valor bruto.
9. Repetir com `NODE_ENV=production` em ambiente de validacao seguro e
   confirmar que o indicador e seu espaco nao sao renderizados.
10. Navegar por teclado e confirmar que o selo nao cria uma parada de foco e
    que o link da marca preserva seu foco visivel.
11. Inspecionar o HTML e confirmar que nenhum valor sensivel ou objeto de
    ambiente foi enviado ao navegador.
12. Encerrar somente o processo temporario iniciado para a validacao e nunca
    iniciar, reutilizar ou interromper processos na porta `3000`.
13. Confirmar que a marca d'agua fica atras dos paineis e nao impede cliques,
    selecao de campos ou navegacao por teclado.
14. Confirmar em desktop e viewport compacta que a marca d'agua nao cria barra
    de rolagem horizontal.
15. Em producao, confirmar que nenhum elemento `.environment-watermark` e
    renderizado.
16. Confirmar que o texto permanece horizontal no topo e que, nas paginas
    autenticadas, nao invade a largura ocupada pela sidebar.

Como o projeto nao possui testes automatizados reais configurados em
`npm test`, a validacao principal deve combinar verificacao de sintaxe e
inspecao visual nas resolucoes desktop e compacta.

---

## Assinatura da LLM

- Data: 2026-07-29 09:54:53 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 2026-07-29 10:37:19 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 2026-07-29 11:16:32 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 2026-07-29 11:24:38 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 2026-07-29 11:28:29 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao
