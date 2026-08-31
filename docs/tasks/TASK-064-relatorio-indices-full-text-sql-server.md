# TASK-064 - Criar relatorio de indices Full-Text do SQL Server

## Contexto

O PS Panel ainda nao possui uma rotina para inventariar indices de pesquisa de
texto completo (Full-Text Search) existentes nas bases de uma instancia SQL
Server.

E necessario consultar o servidor `SERV01D`, percorrer todos os bancos online
visiveis para a identidade de execucao e, quando houver ao menos um indice
Full-Text, enviar um relatorio por email para `dba@desenbahia.ba.gov.br`.

O repositorio ja possui o modulo compartilhado
`scripts-ps/modules/PSPanel.Email/PSPanel.Email.psm1`, que exporta
`Send-PSPanelEmail`. O novo script deve reutilizar esse modulo e nao pode
duplicar configuracoes ou credenciais SMTP.

## Objetivo

Criar um script PowerShell executavel pelo PS Panel que:

1. conecte ao SQL Server `SERV01D` usando autenticacao integrada do Windows;
2. confirme que o recurso Full-Text Search esta instalado na instancia;
3. enumere todos os bancos online visiveis para a identidade de execucao;
4. consulte, em cada banco elegivel, a existencia de indices Full-Text;
5. consolide os indices encontrados em um relatorio HTML seguro e legivel;
6. envie um unico email para `dba@desenbahia.ba.gov.br` somente quando houver
   ao menos um indice encontrado;
7. encerre com codigo diferente de zero se a varredura nao puder ser concluida
   integralmente ou se o envio falhar.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Arquivo proposto

```text
scripts-ps/Relatorio-IndicesFullText-SQLServer.ps1
```

Ao concluir a implementacao, atualizar tambem:

```text
src/config/release.js
```

usando a data local da implementacao e o proximo sequencial global no formato
`vAAAA.MM.DD-NNN`, conforme `AGENTS.md`.

## Dependencias e ambiente de execucao

O script deve:

- exigir PowerShell 5.1 ou superior;
- executar em Windows sob uma identidade com acesso ao SQL Server `SERV01D`;
- usar autenticacao integrada do Windows, sem receber usuario ou senha SQL por
  parametro;
- exigir permissao para visualizar todos os bancos que fazem parte da
  varredura e consultar seus catalogos de sistema;
- utilizar APIs .NET disponiveis no ambiente para acessar o SQL Server, sem
  instalar modulos ou provedores em tempo de execucao;
- abrir conexoes com timeout finito e encerrar corretamente conexoes, comandos
  e leitores, inclusive em caso de erro;
- usar conexao criptografada com `TrustServerCertificate=True`, conforme
  excecao operacional solicitada para `SERV01D`;
- documentar que essa opcao preserva a criptografia do canal, mas nao valida a
  cadeia de confianca nem o nome do certificado apresentado pelo SQL Server;
- importar `PSPanel.Email.psm1` por caminho baseado em `$PSScriptRoot`, sem
  depender do diretorio corrente;
- usar somente a configuracao SMTP compartilhada lida internamente pelo modulo
  de email.

O script nao deve instalar o modulo `SqlServer`, alterar configuracoes da
instancia nem habilitar o recurso Full-Text Search automaticamente.

## Parametros e valores operacionais

Definir os parametros abaixo com valores padrao:

```text
-SqlServer SERV01D
-MailTo dba@desenbahia.ba.gov.br
```

Regras:

- validar que `SqlServer` e `MailTo` nao estejam vazios;
- manter os valores solicitados como defaults para permitir execucao manual ou
  agendada sem argumentos;
- aceitar a substituicao explicita desses valores para testes autorizados de
  homologacao;
- nao aceitar usuario, senha, connection string completa, consulta SQL,
  certificado, comando ou script block fornecido pelo usuario;
- nao registrar o endereco completo de conexao, connection string ou dados de
  autenticacao em `stdout`, `stderr` ou no corpo do email.

O bloco de ajuda comentada deve documentar todos os parametros e conter ao
menos um exemplo que utilize os valores padrao, sem credenciais ou segredos:

```powershell
.\scripts-ps\Relatorio-IndicesFullText-SQLServer.ps1
```

## Escopo da varredura

### Descoberta dos bancos

A conexao inicial deve usar o catalogo `master` e consultar `sys.databases`.
Devem fazer parte da varredura todos os bancos que:

- estejam no estado `ONLINE`;
- estejam visiveis para a identidade de execucao;
- permitam conexao no momento da coleta;
- nao sejam `tempdb`, pois o banco temporario nao deve compor o inventario
  persistente.

Os bancos de sistema que atendam a essas condicoes nao devem ser descartados
apenas pelo seu `database_id`. O relatorio deve informar a quantidade de bancos
enumerados e efetivamente consultados.

Para garantir que a expressao **todos os bancos** represente uma varredura
completa, a identidade de execucao deve possuir visibilidade adequada sobre a
instancia. Se o ambiente nao permitir comprovar essa visibilidade, o script
deve falhar com mensagem clara, em vez de apresentar um resultado parcial como
completo.

### Verificacao do Full-Text Search

Antes da varredura, consultar a propriedade da instancia equivalente a
`FULLTEXTSERVICEPROPERTY('IsFullTextInstalled')`.

- se o recurso nao estiver instalado, encerrar com erro claro e sem enviar um
  relatorio vazio;
- se a propriedade nao puder ser determinada, tratar como falha;
- a rotina deve ser estritamente de leitura e nao tentar instalar, habilitar,
  reparar ou reconfigurar o recurso.

### Consulta em cada banco

Abrir uma conexao direcionada a cada banco enumerado e consultar as views de
catalogo documentadas do SQL Server, incluindo conforme necessario:

- `sys.fulltext_indexes`;
- `sys.fulltext_catalogs`;
- `sys.tables`;
- `sys.schemas`;
- `sys.indexes`;
- `sys.fulltext_index_columns`;
- `sys.columns`;
- `sys.fulltext_languages`.

Nao usar `sp_MSforeachdb`, por ser um procedimento nao documentado. Nao montar
uma consulta executavel por concatenacao com valores fornecidos pelo usuario.
Quando um identificador precisar ser composto, usar abordagem segura e
especifica para identificadores SQL; preferencialmente, selecionar o banco na
propriedade de catalogo da propria conexao.

Para cada indice Full-Text encontrado, coletar no minimo:

- nome do banco;
- schema e tabela;
- catalogo Full-Text;
- indice unico usado como chave;
- estado de habilitacao;
- modo de acompanhamento de alteracoes;
- lista ordenada das colunas indexadas;
- idioma configurado por coluna, quando disponivel.

O resultado deve ser deterministico, ordenado por banco, schema e tabela. Um
indice Full-Text deve aparecer apenas uma vez no resumo, mesmo quando possuir
varias colunas; as colunas e idiomas podem ser apresentados como uma lista no
mesmo registro.

Se qualquer banco enumerado ficar indisponivel, mudar de estado ou retornar
erro durante a consulta, a execucao deve falhar. Nao enviar um relatorio
parcial como se a varredura tivesse sido concluida.

## Regra de envio

O email deve ser enviado apenas quando a varredura completa encontrar um ou
mais indices Full-Text.

Quando nenhum indice for encontrado:

- nao enviar email;
- escrever em `stdout` um resumo informando servidor, quantidade de bancos
  consultados e total zero;
- encerrar com codigo `0`, desde que todas as consultas tenham sido concluidas
  com sucesso.

Quando houver resultados, enviar um unico email por execucao para o valor de
`MailTo` usando exclusivamente `Send-PSPanelEmail`.

## Conteudo do email

### Assunto

Usar assunto curto e em portugues, por exemplo:

```text
PS Panel - Indices Full-Text encontrados em SERV01D (3)
```

O total entre parenteses deve representar a quantidade de indices, e nao a
quantidade de colunas indexadas.

### Corpo HTML

O relatorio deve conter:

- titulo **Indices Full-Text encontrados no SQL Server**;
- servidor consultado;
- data e hora local da coleta;
- quantidade de bancos enumerados e consultados;
- quantidade total de indices encontrados;
- resumo por banco;
- tabela ou blocos com os campos definidos nesta task;
- aviso de que a coleta e informativa e representa o estado observado naquele
  instante;
- rodape padrao com data do envio, sistema `PS Panel`, nome da rotina e nome do
  host obtido em tempo de execucao.

O HTML deve usar estilos inline simples e nao depender de JavaScript, CSS
externo, imagens remotas ou recursos hospedados pelo PS Panel.

Todos os valores originados do SQL Server ou recebidos por parametro devem
receber HTML encoding antes de entrar no assunto ou corpo. O nome do servidor
usado no exemplo de assunto nao deve ser interpolado sem escape na
implementacao.

## Ajuda comentada e saida operacional

O arquivo deve iniciar com `#requires -Version 5.1` e possuir comment-based
help antes de `[CmdletBinding()]` e `param(...)`, contendo:

- `.SYNOPSIS` usado pelo PS Panel como descricao;
- `.DESCRIPTION` com o fluxo e a regra de envio condicional;
- uma secao `.PARAMETER` para cada parametro;
- `.EXAMPLE` executavel e sem credenciais;
- `.INPUTS`;
- `.OUTPUTS`;
- `.NOTES` com dependencias, permissoes e pre-requisitos de TLS, SQL Server e
  Full-Text Search.

Em caso de sucesso com ou sem achados, `stdout` deve conter somente um resumo
operacional seguro: servidor, quantidade de bancos consultados, total de
indices e se o email foi enviado. Nao imprimir o HTML completo nem uma lista
completa de objetos no console.

## Seguranca

- Nao armazenar nem receber credenciais SQL ou SMTP no script.
- Nao usar autenticacao SQL; usar a identidade Windows do processo.
- Nao incluir `Integrated Security` junto com usuario ou senha.
- Nao desabilitar a criptografia da conexao SQL.
- Usar `TrustServerCertificate=True` somente nesta rotina e documentar que a
  autenticidade do certificado SQL nao sera validada.
- Nao aplicar essa excecao ao TLS do modulo `PSPanel.Email`, que deve continuar
  validando normalmente o certificado SMTP.
- Nao executar DDL, DML ou procedimentos que alterem servidor, bancos,
  catalogos, tabelas ou indices.
- Nao registrar connection string, tokens, headers, credenciais ou o conteudo
  de `database/email-settings.json`.
- Nao imprimir o corpo HTML completo.
- Escapar todos os dados dinamicos antes de inseri-los no HTML.
- Usar exclusivamente `Send-PSPanelEmail`; nao usar `Send-MailMessage` nem
  `System.Net.Mail.SmtpClient`.
- Nao modificar `PSPanel.Email.psm1` sem que um defeito reproduzivel seja
  identificado e o aumento de escopo seja aprovado.

## Tratamento de erros e codigo de saida

Usar erros terminantes nas etapas criticas e um fluxo principal com
`try/catch/finally`.

Devem encerrar com codigo diferente de zero:

- parametro obrigatorio vazio ou invalido;
- falha de DNS, TLS, autenticacao, autorizacao ou conexao com `SERV01D`;
- falta de visibilidade necessaria para uma varredura completa;
- Full-Text Search ausente ou impossivel de verificar;
- falha ao enumerar os bancos;
- falha ao conectar ou consultar qualquer banco enumerado;
- falha ao carregar ou importar o modulo `PSPanel.Email` quando houver
  resultados;
- configuracao SMTP ausente ou invalida quando houver resultados;
- falha de conexao, autenticacao, TLS ou envio SMTP.

As mensagens devem ser claras, em portugues, identificar a etapa geral da
falha e nao expor connection string, stack trace por padrao, consultas
completas, credenciais ou corpo do email.

Uma falha de consulta nunca deve ser convertida em resultado zero. Um email
somente pode ser enviado depois que todos os bancos enumerados forem
consultados com sucesso.

## Fluxo esperado

```text
validar parametros
  -> abrir conexao integrada com master
  -> verificar instalacao do Full-Text Search
  -> enumerar todos os bancos online elegiveis
  -> consultar os catalogos de cada banco
  -> falhar se qualquer parte da varredura for incompleta
  -> consolidar e ordenar os indices encontrados
  -> se total = 0, imprimir resumo e encerrar com sucesso sem email
  -> importar PSPanel.Email pelo caminho relativo ao script
  -> montar HTML com encoding e rodape padrao
  -> enviar um unico email
  -> imprimir resumo seguro e encerrar com sucesso
```

## Integracao com o PS Panel

O script deve permanecer em `scripts-ps/` para ser descoberto e executado pelos
fluxos existentes. Nao criar rota, controller, view, model, tabela SQLite ou
worker.

O agendamento, quando desejado, deve usar a funcionalidade existente do PS
Panel. Com os valores padrao desta task, nao sera necessario informar
parametros para consultar `SERV01D` e enviar ao destinatario solicitado.

## Fora de escopo

- Criar, remover, reconstruir, popular, pausar ou reorganizar indices
  Full-Text.
- Instalar ou habilitar o componente Full-Text Search.
- Alterar configuracoes do SQL Server ou de qualquer banco.
- Consultar conteudo das tabelas indexadas.
- Executar verificacao de integridade ou medir desempenho dos indices.
- Consultar servidores SQL adicionais na mesma execucao.
- Persistir o inventario em SQLite ou em arquivo.
- Criar dashboard, rota, controller, view ou worker.
- Alterar a configuracao SMTP compartilhada.
- Alterar o parser global de parametros do PS Panel.
- Atualizar dependencias, `package-lock.json` ou provedores externos.
- Enviar email quando a varredura completa terminar sem indices encontrados.

## Arquivos previstos

```text
scripts-ps/Relatorio-IndicesFullText-SQLServer.ps1
src/config/release.js
```

O modulo abaixo deve ser apenas consumido:

```text
scripts-ps/modules/PSPanel.Email/PSPanel.Email.psm1
```

## Criterios de aceite

- O script existe em `scripts-ps/` e e descoberto pelo PS Panel.
- O comment-based help segue integralmente o padrao de `docs/patterns.md`.
- `SqlServer` usa `SERV01D` como valor padrao.
- `MailTo` usa `dba@desenbahia.ba.gov.br` como valor padrao.
- A conexao usa autenticacao integrada e nao recebe credenciais.
- A conexao exige criptografia e usa `TrustServerCertificate=True` por excecao
  operacional explicita desta task.
- A documentacao informa que o certificado SQL nao tem cadeia ou nome
  validados e que a excecao nao se aplica ao SMTP.
- A instalacao do Full-Text Search e verificada antes da varredura.
- Todos os bancos online visiveis e conectaveis, exceto `tempdb`, sao
  consultados, sem exclusao generica dos bancos de sistema.
- A execucao falha se nao puder comprovar ou concluir a varredura completa.
- A consulta usa views de catalogo documentadas e nao usa `sp_MSforeachdb`.
- O script nao altera o SQL Server nem consulta dados das tabelas indexadas.
- Cada indice aparece uma vez, com banco, schema, tabela, catalogo, chave,
  estado, acompanhamento de alteracoes, colunas e idiomas.
- O resultado e ordenado deterministicamente por banco, schema e tabela.
- Nenhum indice encontrado encerra com sucesso e nao envia email.
- Um ou mais indices encontrados geram exatamente um email.
- O assunto informa o servidor e a quantidade de indices.
- O corpo informa horario, cobertura da varredura, resumo por banco e detalhes
  dos indices.
- Todo dado dinamico recebe HTML encoding.
- O email possui o rodape obrigatorio de `docs/patterns.md`, com o hostname
  obtido em tempo de execucao.
- O envio usa `Send-PSPanelEmail` e nao duplica configuracao SMTP.
- O console apresenta apenas resumo seguro e nunca imprime o corpo HTML.
- Falhas de SQL Server ou email resultam em codigo diferente de zero.
- O release e incrementado somente quando a task for implementada.

## Testes sugeridos

1. Validar o parse do arquivo PowerShell sem executar conexoes externas.
2. Executar com parametro vazio e confirmar falha antes de acessar o servidor.
3. Simular falha de DNS ou conexao e confirmar mensagem clara e codigo de
   erro; em homologacao, confirmar que um certificado SQL nao confiavel nao
   impede a conexao e que a criptografia permanece habilitada.
4. Executar sem permissao suficiente e confirmar que nenhum email e enviado.
5. Simular Full-Text Search ausente e confirmar falha sem tentativa de
   instalacao.
6. Validar uma instancia sem indices e confirmar codigo `0`, resumo no console
   e ausencia de email.
7. Criar ou usar em homologacao indices Full-Text com uma e varias colunas e
   validar a consolidacao.
8. Validar indices em bancos distintos e confirmar ordenacao e resumo por
   banco.
9. Tornar um banco enumerado indisponivel durante a coleta e confirmar falha
   sem envio parcial.
10. Usar nomes de banco, schema, tabela ou coluna com caracteres especiais e
    confirmar encoding e renderizacao segura.
11. Simular configuracao SMTP ausente e falha SMTP, confirmando codigo de erro
    somente quando existirem achados que exijam envio.
12. Inspecionar `stdout`, `stderr` e historico para confirmar ausencia de
    connection strings, credenciais e corpo HTML.
13. Confirmar o rodape com data, sistema, rotina e hostname.
14. Executar pelo fluxo manual e por agendamento do PS Panel em ambiente de
    homologacao autorizado.

Todos os testes com SQL Server e SMTP devem ocorrer apenas em ambiente
autorizado. Nao imprimir nem documentar credenciais, connection strings reais,
conteudo do `.env` ou de `database/email-settings.json`.

## Validacao esperada na implementacao

Validar a sintaxe sem executar a consulta:

```powershell
powershell.exe -NoProfile -Command "$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\scripts-ps\Relatorio-IndicesFullText-SQLServer.ps1'), [ref]$null, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }"
```

Validar o arquivo de release alterado:

```powershell
node --check src\config\release.js
```

Quando houver acesso autorizado ao SQL Server e SMTP de homologacao, executar
os testes funcionais sugeridos. A validacao nao deve iniciar nem reutilizar um
servidor web na porta `3000`.

---

## Assinatura da LLM

- Data: 2026-08-31 14:02:02 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

- Status: implementada em 2026-08-31.
- Criado `scripts-ps/Relatorio-IndicesFullText-SQLServer.ps1` com conexao
  integrada, criptografia, `TrustServerCertificate=True`, validacao de
  cobertura e consulta somente leitura aos catalogos documentados do SQL
  Server.
- O relatorio usa `Send-PSPanelEmail` e so envia email quando existem indices
  Full-Text; resultado vazio encerra com sucesso sem envio.
- Adicionados testes determinísticos para os requisitos estruturais e de
  seguranca, sem acessar SQL Server ou SMTP reais.
- O release foi atualizado para `v2026.08.31-071`.

---

## Assinatura da LLM

- Data: 2026-08-31 14:18:14 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 2026-08-31 15:36:19 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao
