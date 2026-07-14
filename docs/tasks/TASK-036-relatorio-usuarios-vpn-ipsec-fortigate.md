# TASK-036 - Relatorio diario de usuarios VPN IPsec do FortiGate

## Atualizacao de escopo - API REST e scripts especialistas

Por decisao posterior, a implementacao por SSH foi substituida por duas coletas independentes usando exclusivamente a API REST HTTPS do proprio FortiGate, sem FortiAnalyzer:

- `scripts-ps/Relatorio-VPN-IPSec-Historico.ps1`: consulta o historico diario na Log API, com `DataRelatorio` opcional e data atual como padrao;
- `scripts-ps/Relatorio-VPN-IPSec-SessoesAtuais.ps1`: consulta as sessoes existentes no instante da coleta em `GET /api/v2/monitor/vpn/ipsec`.

Esta atualizacao prevalece sobre as referencias a SSH, Posh-SSH, credenciais `FortiUser`/`FortiPassword`, arquivo unico e e-mail unico existentes nas secoes originais desta task. O script combinado `Relatorio-VPN-IPSec.ps1` fica preservado apenas como implementacao legada e nao e alterado neste escopo.

Requisitos atualizados:

- os dois scripts devem receber `FortiApiToken` obrigatorio e usar o cabecalho `Authorization: Bearer`, sem imprimir o token;
- `FortiGateIP`, `FortiGatePort`, `Vdom` e validacao de certificado devem ser configuraveis;
- o historico deve usar por padrao `/api/v2/log/disk/event/vpn`, filtrar `date` e `action=tunnel-up`, acompanhar consultas assincronas por `session_id` ate `ready=true` e paginar sem truncamento silencioso;
- o historico deve permitir ajustar `LogApiPath` para compatibilidade controlada com outra versao do FortiOS;
- as sessoes atuais devem incluir apenas entradas dial-up/dynamic com usuario identificado, excluindo tuneis site-to-site sem usuario;
- cada especialista deve gerar e enviar seu proprio e-mail HTML, inclusive quando a respectiva consulta nao encontrar registros;
- ambos devem funcionar no Windows PowerShell 5.1 e no PowerShell 7, aplicar HTML encode aos dados externos e restaurar qualquer callback temporario de certificado;
- nao usar SSH, `execute log display`, comandos `diagnose`, FortiAnalyzer ou alteracoes persistentes no FortiGate.

Criterios de aceite atualizados:

- os dois novos arquivos especialistas existem em `scripts-ps/` e sao reconhecidos pelo parser de parametros do PS Panel;
- a omissao de `DataRelatorio` usa a data atual e datas inexistentes sao rejeitadas antes da chamada HTTP;
- a Log API e consultada ate finalizar a pesquisa e todas as paginas informadas pela resposta sao coletadas ou a execucao falha explicitamente;
- a API de monitoramento produz uma linha por sessao autenticada atual e nao classifica tunel estatico como sessao de usuario;
- falhas HTTP, respostas incompletas e falhas SMTP encerram o script com codigo diferente de zero;
- token, resposta bruta e outros dados sensiveis nao sao escritos na saida operacional.

## Contexto

O repositorio possui o script `scripts-ps/Monitoramento-VPN.ps1`, que acessa o FortiGate por SSH com o modulo Posh-SSH, consulta sessoes SSL VPN e envia um alerta em HTML por e-mail usando `System.Net.Mail.SmtpClient`.

E necessario criar um novo script PowerShell para relatar usuarios autenticados em VPN IPsec. O relatorio deve mostrar tanto as conexoes ocorridas em uma data de referencia quanto as conexoes IPsec existentes no momento da execucao.

O historico diario e as sessoes ativas sao fontes diferentes no FortiGate: as conexoes do dia devem ser obtidas dos logs de eventos VPN, enquanto as conexoes atuais devem ser obtidas do estado IKE/IPsec. A implementacao deve considerar que comandos e formatos de saida podem variar entre versoes do FortiOS.

## Objetivo

Criar o script `scripts-ps/Relatorio-VPN-IPSec.ps1` para consultar o FortiGate por SSH, gerar um relatorio HTML com duas tabelas e envia-lo por e-mail seguindo o mecanismo de envio usado em `scripts-ps/Monitoramento-VPN.ps1`.

As tabelas devem apresentar:

1. conexoes de usuarios VPN IPsec registradas na data informada;
2. conexoes de usuarios VPN IPsec ativas no momento da execucao.

## Escopo

- Criar somente o novo script `scripts-ps/Relatorio-VPN-IPSec.ps1`.
- Receber as credenciais SSH do FortiGate por parametros obrigatorios.
- Receber a data do relatorio por parametro opcional.
- Usar a data atual quando o parametro de data nao for informado.
- Consultar os logs do FortiGate referentes ao dia completo selecionado.
- Filtrar somente eventos de conexao de usuarios VPN IPsec.
- Consultar separadamente as sessoes IPsec ativas no momento da execucao.
- Gerar um e-mail HTML com resumo, duas tabelas e identificacao da data de referencia e do horario de execucao.
- Enviar o relatorio mesmo quando uma ou ambas as tabelas estiverem vazias.
- Reaproveitar os padroes de conexao SSH, codificacao HTML, SMTP e encerramento de sessao de `Monitoramento-VPN.ps1`, sem alterar o script existente.

## Fora de escopo

- Alterar `scripts-ps/Monitoramento-VPN.ps1`.
- Alterar rotas, controllers, views ou models da aplicacao WEB.
- Criar tela especifica para o relatorio.
- Persistir o resultado em SQLite ou em arquivos locais.
- Instalar ou configurar armazenamento de logs no FortiGate.
- Consultar FortiAnalyzer, FortiManager, syslog externo ou outra fonte de logs.
- Incluir tuneis IPsec site-to-site sem usuario autenticado no relatorio de usuarios.
- Derrubar, renovar ou modificar sessoes VPN.
- Atualizar dependencias Node.js ou `package-lock.json`.

## Nome e parametros esperados

O novo arquivo deve se chamar:

```text
scripts-ps/Relatorio-VPN-IPSec.ps1
```

Parametros minimos:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FortiUser,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FortiPassword,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FortiGateIP = "10.35.0.1",

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$DataRelatorio = (Get-Date).ToString('yyyy-MM-dd')
)
```

Regras do parametro `DataRelatorio`:

- aceitar o formato ISO `yyyy-MM-dd`;
- ser opcional;
- assumir a data atual do ambiente quando omitido;
- rejeitar datas inexistentes, mesmo quando o texto atender ao formato;
- interpretar o intervalo no fuso horario configurado no FortiGate;
- abranger de `00:00:00` ate `23:59:59` da data selecionada;
- nao alterar a data recebida em funcao do fuso horario do processo local.

Exemplos esperados:

```powershell
.\Relatorio-VPN-IPSec.ps1 -FortiUser "usuario" -FortiPassword "senha"
.\Relatorio-VPN-IPSec.ps1 -FortiUser "usuario" -FortiPassword "senha" -DataRelatorio "2026-07-12"
```

Os exemplos devem usar apenas valores ficticios e nunca credenciais reais.

## Levantamento tecnico obrigatorio

Antes de finalizar o parser, validar em ambiente controlado a versao do FortiOS e capturar amostras anonimizadas das saidas dos comandos disponiveis para:

- filtrar e exibir logs de eventos VPN IPsec no intervalo solicitado;
- listar gateways IKE e sessoes IPsec ativas;
- identificar usuario autenticado, IP de origem, IP atribuido ao cliente, nome do tunel e timestamps.

Como referencia inicial, avaliar os comandos da familia `execute log filter`/`execute log display` para o historico e `diagnose vpn ike gateway list` para o estado atual. A implementacao nao deve assumir cegamente uma sintaxe ou posicao fixa de colunas sem confirmar a saida do FortiOS usado no ambiente.

Registrar comentarios no script explicando quais formatos de saida foram suportados. Nao incluir nas amostras nomes reais de usuarios, IPs internos, credenciais ou outros dados sensiveis.

## Requisitos funcionais

1. O script deve conectar ao equipamento indicado em `FortiGateIP` usando `FortiUser` e `FortiPassword`.
2. Quando `DataRelatorio` for omitido, o assunto, o resumo e a consulta historica devem usar o dia atual.
3. Quando `DataRelatorio` for informado, somente eventos pertencentes ao dia selecionado devem entrar na primeira tabela.
4. A primeira tabela deve conter uma linha por conexao identificada, preservando conexoes repetidas do mesmo usuario em horarios diferentes.
5. Eventos de desconexao isolados, falhas de autenticacao e tuneis site-to-site sem usuario nao devem ser classificados como uma nova conexao de usuario.
6. Quando o formato do log permitir correlacao confiavel, a linha historica deve ser enriquecida com termino e duracao da sessao; a ausencia desses dados nao deve descartar uma conexao valida.
7. A segunda tabela deve refletir as sessoes IPsec de usuarios existentes no instante da consulta, independentemente da data selecionada para o historico.
8. A consulta de sessoes ativas deve ocorrer o mais proximo possivel da geracao do e-mail, e o horario da coleta deve ser exibido no relatorio.
9. O e-mail deve ser enviado em todas as execucoes bem-sucedidas, inclusive quando nao houver conexoes historicas ou ativas.
10. Uma tabela vazia deve exibir uma mensagem amigavel, como `Nenhuma conexao encontrada`, e nao apenas um cabecalho sem linhas.
11. O assunto deve identificar que se trata de relatorio VPN IPsec e incluir a data de referencia no formato `dd/MM/yyyy`.
12. O corpo deve informar o FortiGate consultado, a data do historico, o horario de execucao e a quantidade de registros em cada tabela.
13. O script deve escrever em `stdout` apenas mensagens operacionais resumidas, sem expor credenciais ou a saida bruta sensivel do equipamento.
14. Falhas de validacao, SSH, consulta, parse ou envio de e-mail devem produzir mensagem clara em `stderr` e encerrar com codigo diferente de zero.
15. Uma falha na consulta historica ou na consulta de sessoes ativas nao deve resultar em e-mail apresentado como relatorio completo e bem-sucedido.

## Colunas do relatorio

### Tabela 1 - Conexoes do dia

Incluir, quando disponivel na saida do FortiGate:

- usuario;
- grupo;
- data/hora da conexao;
- data/hora da desconexao;
- duracao;
- IP publico/de origem;
- IP atribuido ao cliente;
- nome do tunel ou gateway;
- resultado ou estado.

Ordenar por data/hora de conexao em ordem crescente. Campos nao fornecidos pelo FortiGate devem ser exibidos como `—`, sem inventar valores.

### Tabela 2 - Conexoes ativas

Incluir, quando disponivel:

- usuario;
- grupo;
- horario de inicio;
- duracao ate a coleta;
- IP publico/de origem;
- IP atribuido ao cliente;
- nome do tunel ou gateway;
- estado da sessao.

Ordenar por usuario e, em seguida, pelo horario de inicio. Tuneis sem usuario autenticado devem ser ignorados ou identificados separadamente no diagnostico, mas nao incluidos nesta tabela.

## Requisitos tecnicos

- Usar funcoes pequenas para validacao da data, execucao de comando SSH, parse do historico, parse das sessoes ativas, geracao do HTML e envio SMTP.
- Usar `Set-StrictMode` e tratamento de erros compativel com a versao de PowerShell adotada pelo projeto, desde que isso nao quebre o fluxo de limpeza no `finally`.
- Reutilizar Posh-SSH conforme o script de referencia e documentar a versao minima necessaria.
- Evitar instalar modulos silenciosamente durante uma execucao agendada. Se Posh-SSH nao estiver disponivel ou estiver abaixo da versao minima, falhar com instrucao clara de instalacao.
- Executar comandos somente na sessao SSH criada pelo script, sem concatenar credenciais nos comandos.
- Tratar a saida do FortiGate como colecao de linhas e tolerar `CRLF` e `LF`.
- Nao depender exclusivamente de espacamento visual quando a saida possuir pares `chave=valor` ou delimitadores mais seguros.
- Nao usar `Invoke-Expression`.
- Nao usar `Send-MailMessage`; manter `System.Net.Mail.SmtpClient` para consistencia com o script de referencia.
- Usar UTF-8 no assunto e no corpo do e-mail.
- Codificar com HTML encode todos os valores obtidos do FortiGate antes de inclui-los no corpo.
- Garantir que a sessao SSH, `MailMessage` e `SmtpClient` sejam descartados em blocos `finally`.
- Nao adicionar `ExecutionPolicy Bypass` ao script.
- Incluir comment-based help com synopsis, descricao dos parametros e exemplos ficticios.

## Configuracao de e-mail

- Seguir inicialmente os mesmos campos de configuracao SMTP de `Monitoramento-VPN.ps1`: servidor, porta, remetente, destinatarios, uso de SSL e uso opcional de credencial SMTP.
- Manter essas configuracoes concentradas em uma secao identificada no inicio do script.
- Permitir multiplos destinatarios separados por virgula ou ponto e virgula, como no script de referencia.
- Nao registrar senha SMTP, credencial SSH ou objetos `PSCredential`.
- Nao documentar valores secretos reais.
- Se autenticacao SMTP estiver desabilitada, nao criar nem imprimir credencial SMTP desnecessariamente.

## Requisitos de seguranca

- Nunca imprimir `FortiPassword`, senha SMTP ou credenciais derivadas.
- Nao incluir a linha de comando completa com valores sensiveis em logs.
- Nao enviar a saida bruta do FortiGate no e-mail.
- Aplicar HTML encode a usuario, grupo, enderecos, nome do tunel, estado e demais campos externos.
- Evitar desabilitar validacao de certificado globalmente. Se a opcao existente de ignorar erros for mantida para SMTP, restaure obrigatoriamente o callback anterior em `finally`.
- Encerrar a sessao SSH mesmo quando houver erro de comando, parse ou SMTP.
- Nao alterar politicas, filtros persistentes ou configuracoes do FortiGate; os comandos devem ser somente de consulta.
- Nao armazenar credenciais, logs brutos ou relatorios em disco.

## Tratamento de limitacoes do FortiGate

- Se o equipamento nao possuir logs locais do periodo selecionado, o script deve diferenciar `nenhuma conexao encontrada` de `fonte de logs indisponivel ou sem retencao suficiente`.
- Se o FortiGate nao registrar o nome do usuario nos eventos IPsec, o script deve informar que nao foi possivel produzir o relatorio de usuarios, em vez de atribuir o evento a um usuario ficticio.
- Se houver paginacao ou limite de resultados na CLI, a consulta deve percorrer todas as paginas necessarias para o dia ou informar explicitamente que o resultado foi truncado.
- Se a versao do FortiOS exigir outra sintaxe, concentrar essa variacao em funcoes de consulta e parse, evitando duplicar a geracao do relatorio.
- O script deve restaurar ou limpar filtros temporarios da CLI quando aplicavel, sem modificar configuracao persistente.

## Sugestao de implementacao

1. Validar `DataRelatorio` com `DateTime.TryParseExact` usando cultura invariavel e construir os limites textuais do dia sem conversao implicita de fuso.
2. Validar a disponibilidade e a versao do Posh-SSH antes de abrir a conexao.
3. Criar a credencial SSH em memoria e abrir uma unica sessao com timeout.
4. Aplicar os filtros de log suportados pelo FortiOS e coletar todos os eventos VPN IPsec do intervalo.
5. Converter os eventos de conexao em objetos `PSCustomObject` normalizados.
6. Correlacionar desconexoes somente quando houver identificador confiavel de sessao/tunel e manter a conexao mesmo quando o termino nao existir.
7. Consultar o estado IKE/IPsec atual e converter apenas sessoes autenticadas de usuarios em objetos normalizados.
8. Gerar o HTML a partir dos objetos, aplicando encode campo a campo.
9. Enviar um unico e-mail contendo resumo e as duas tabelas.
10. Encerrar e descartar recursos em `finally` e retornar codigo de saida coerente.

## Criterios de aceite

- O arquivo `scripts-ps/Relatorio-VPN-IPSec.ps1` e criado sem alterar `Monitoramento-VPN.ps1`.
- `FortiUser` e `FortiPassword` sao obrigatorios; `FortiGateIP` e `DataRelatorio` sao opcionais.
- A omissao de `DataRelatorio` consulta o dia atual.
- Uma data valida no formato `yyyy-MM-dd` limita a primeira tabela ao dia informado.
- Texto com formato incorreto ou data inexistente e rejeitado antes da conexao SSH.
- A primeira tabela apresenta somente conexoes de usuarios VPN IPsec e preserva reconexoes do mesmo usuario.
- A segunda tabela apresenta as conexoes IPsec de usuarios existentes no momento da execucao.
- Sessoes ativas sao consultadas mesmo quando a data historica e anterior ao dia atual.
- Tuneis site-to-site sem usuario e falhas de autenticacao nao aparecem como conexoes de usuarios.
- O e-mail contem as duas tabelas, totais, data de referencia, horario da coleta e identificacao do FortiGate.
- O e-mail e enviado mesmo quando nao ha registros, com estados vazios claros.
- Todos os campos vindos do FortiGate sao codificados antes de entrar no HTML.
- Credenciais e saida bruta nao aparecem em `stdout`, `stderr`, e-mail ou documentacao.
- Falhas de consulta ou envio resultam em codigo de saida diferente de zero.
- A sessao SSH e os objetos SMTP sao encerrados inclusive nos fluxos de erro.
- O script funciona quando executado diretamente e pelo fluxo existente do PS Panel com parametros nomeados.

## Testes sugeridos

- Executar `DataRelatorio` omitido e confirmar que o dia atual aparece no assunto e na primeira tabela.
- Executar com uma data anterior valida e confirmar que nenhum evento fora daquele dia aparece no historico.
- Testar ano bissexto e datas invalidas, como `2026-02-29`, `2026-13-01` e formato `13/07/2026`.
- Testar um dia com varias conexoes do mesmo usuario e confirmar que todas sao preservadas.
- Testar um dia sem conexoes e confirmar o estado vazio e o envio do e-mail.
- Testar sessoes ativas com e sem usuario autenticado e confirmar que somente as sessoes de usuario aparecem.
- Testar uma data passada enquanto existe uma sessao ativa e confirmar que ela aparece somente na segunda tabela, salvo se tambem houver evento historico correspondente no dia escolhido.
- Testar campos com `&`, `<`, `>`, aspas e texto semelhante a HTML e confirmar que nao sao interpretados no e-mail.
- Testar indisponibilidade SSH, credencial invalida, timeout, comando nao suportado, log sem retencao e falha SMTP.
- Confirmar que falhas retornam codigo diferente de zero e que a sessao SSH e encerrada.
- Validar manualmente a saida contra amostras anonimizadas reais da versao do FortiOS usada no ambiente.
- Executar analise sintatica sem disparar a logica principal, por exemplo criando um AST com o parser do PowerShell.
- Executar o script em ambiente controlado com destinatario de teste antes de habilitar um agendamento de producao.

## Validacao esperada

- Validar a sintaxe do arquivo PowerShell criado.
- Validar os parsers com amostras anonimizadas de: conexao, desconexao, falha de autenticacao, tunel site-to-site, sessao ativa e saida vazia.
- Confirmar o intervalo da data no fuso do FortiGate.
- Inspecionar o HTML recebido nos clientes de e-mail usados pela equipe.
- Confirmar codigo de saida zero somente quando consultas, geracao e envio forem concluidos com sucesso.
- Rodar `git status --short` e confirmar que nenhum arquivo de credencial, log bruto, banco ou relatorio gerado foi adicionado.

## Dependencias e riscos

- O relatorio historico depende de o FortiGate manter localmente os logs de eventos VPN do periodo solicitado e permitir sua consulta pela conta SSH.
- O nome do usuario pode nao estar presente em todos os tipos de VPN IPsec ou metodos de autenticacao.
- A sintaxe dos comandos e o formato das saidas variam entre versoes do FortiOS; amostras do equipamento alvo sao necessarias para concluir o parser com seguranca.
- A conta SSH deve possuir permissao de leitura dos logs e do estado VPN, sem necessidade de permissao para alterar configuracoes.
- Um volume elevado de logs pode exigir paginacao e limites para evitar timeout ou truncamento silencioso.

---

## Assinatura da LLM

- Data: 2026-07-13
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 2026-07-14
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao
