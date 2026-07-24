# TASK-050 - Criar relatorio por email de contas bloqueadas no Active Directory

## Contexto

O PS Panel ainda nao possui um script PowerShell para identificar contas de
usuario bloqueadas no Active Directory e enviar o resultado por email.

O repositorio ja possui a configuracao SMTP centralizada e o modulo
`scripts-ps/modules/PSPanel.Email/PSPanel.Email.psm1`, que exporta
`Send-PSPanelEmail`. O novo script deve reutilizar esse modulo, sem duplicar
host, porta, remetente ou credenciais SMTP.

No contexto desta task, a expressao **senha bloqueada** sera interpretada como
**conta de usuario atualmente bloqueada no AD por causa da politica de
bloqueio**, isto e, o estado `LockedOut`.

Senha expirada, senha que nunca expira, usuario obrigado a trocar a senha no
proximo logon e conta desabilitada sao estados diferentes e nao devem ser
usados como criterio de inclusao. Uma conta simultaneamente bloqueada e
desabilitada deve aparecer no relatorio, com o estado desabilitado identificado
em coluna propria.

## Objetivo

Criar um script PowerShell executavel pelo PS Panel que:

1. consulte o dominio Active Directory da identidade que executa o script e
   descubra todos os seus controladores de dominio;
2. localize em cada controlador as contas de usuario atualmente bloqueadas;
3. consulte em cada controlador os atributos locais de senha incorreta;
4. gere um relatorio HTML seguro, legivel, ordenado e consolidado por conta;
5. envie o relatorio aos destinatarios informados usando o modulo compartilhado
   `PSPanel.Email`;
6. envie tambem um relatorio de estado vazio quando nenhuma conta estiver
   bloqueada;
7. encerre com codigo diferente de zero quando a consulta ao AD ou o envio do
   email falhar.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Arquivo proposto

```text
scripts-ps/Relatorio-ContasAD-Bloqueadas.ps1
```

Ao concluir a implementacao, atualizar tambem:

```text
src/config/release.js
```

com a data local da implementacao e o proximo sequencial global no formato
`vAAAA.MM.DD-NNN`, conforme `AGENTS.md`.

## Dependencias e ambiente de execucao

O script deve:

- ser executado em Windows por uma identidade de dominio com permissao de
  leitura sobre os objetos de usuario consultados;
- exigir o modulo Microsoft `ActiveDirectory`, normalmente disponibilizado
  pelas ferramentas RSAT ou pelo Windows Server;
- importar explicitamente o modulo `ActiveDirectory` com erro terminante;
- nao instalar RSAT, modulos PowerShell ou qualquer dependencia em tempo de
  execucao;
- nao solicitar nem receber credenciais do AD por parametros;
- usar a identidade do processo que executa o PS Panel ou o agendamento;
- importar `PSPanel.Email.psm1` por caminho baseado em `$PSScriptRoot`, sem
  depender do diretorio corrente;
- usar somente a configuracao SMTP compartilhada em
  `database/email-settings.json`, lida internamente pelo modulo de email.

Se o modulo `ActiveDirectory` nao estiver disponivel, o script deve falhar antes
da consulta e apresentar uma mensagem clara em portugues, sem tentar corrigir o
servidor automaticamente.

## Parametros

### Destinatarios

Definir um parametro obrigatorio:

```text
-MailTo
```

O parametro deve aceitar um ou mais enderecos. Para facilitar a execucao pelo
PS Panel e por agendamentos, uma unica string pode conter destinatarios
separados por virgula ou ponto e virgula, conforme ja suportado por
`Send-PSPanelEmail`.

Nao gravar endereco organizacional real como valor padrao no codigo. A ausencia
de destinatario deve causar erro de validacao antes da consulta ao AD.

Exemplos de uso esperados:

```powershell
.\scripts-ps\Relatorio-ContasAD-Bloqueadas.ps1 -MailTo 'seguranca@exemplo.local'
.\scripts-ps\Relatorio-ContasAD-Bloqueadas.ps1 -MailTo 'seguranca@exemplo.local;suporte@exemplo.local'
```

Os exemplos devem usar apenas dominios ficticios e nunca conter dados reais do
ambiente.

### Parametros fora do escopo inicial

Nao adicionar nesta primeira versao:

- usuario ou senha do AD;
- host, porta, remetente, usuario ou senha SMTP;
- filtro LDAP arbitrario;
- comando PowerShell arbitrario;
- opcao para ignorar validacao de certificado;
- opcao para desbloquear contas;
- opcao para instalar automaticamente o modulo `ActiveDirectory`.

Uma `SearchBase` configuravel e consulta a multiplos dominios ou florestas ficam
fora do escopo. A primeira versao deve consultar todo o dominio atual.

## Consulta ao Active Directory

### Dominio e controladores consultados

Existe somente um PDC Emulator por dominio. Para apresentar o estado local de
cada origem e obter o horario de senha incorreta mais recente do dominio:

1. obter o dominio atual com `Get-ADDomain`;
2. identificar o PDC Emulator pelo atributo `PDCEmulator`;
3. descobrir todos os controladores do dominio com `Get-ADDomainController`;
4. usar explicitamente cada controlador no parametro `-Server` das consultas
   correspondentes;
5. identificar no relatorio qual controlador exerce o papel de PDC Emulator;
6. registrar dominio, controladores, site, estado de somente leitura, horario de
   cada consulta e horario final da coleta.

Se nao for possivel descobrir ou consultar qualquer controlador retornado, a
execucao deve falhar. Nao enviar uma consolidacao parcial como se representasse
todo o dominio.

### Criterio de selecao

Usar uma consulta propria do modulo `ActiveDirectory`, preferencialmente:

```powershell
Search-ADAccount -LockedOut -UsersOnly -Server <CONTROLADOR>
```

A consulta deve ser repetida em todos os controladores descobertos, abranger o
dominio atual e retornar somente objetos de usuario. Nao incluir computadores.
A lista consolidada deve ser a uniao por `DistinguishedName`, sem duplicar a
mesma conta encontrada em mais de um controlador.

Nao substituir o criterio por:

- `Enabled -eq $false`;
- `PasswordExpired`;
- `PasswordNeverExpires`;
- `ChangePasswordAtLogon`;
- texto encontrado em descricao, grupo ou unidade organizacional.

Contas desabilitadas nao devem ser filtradas quando tambem estiverem
bloqueadas. O relatorio deve permitir que o destinatario diferencie os dois
estados.

### Enriquecimento dos dados

Para cada conta presente na uniao, chamar `Get-ADUser` em cada controlador,
sempre com `-Server` explicito, e solicitar apenas os atributos necessarios ao
relatorio.

Campos previstos:

- `SamAccountName`;
- nome de exibicao;
- `UserPrincipalName`;
- `Enabled`;
- `LockedOut`;
- horario de bloqueio, quando disponivel;
- `badPasswordTime`, apresentado como ultima tentativa de senha incorreta
  observada naquele controlador;
- quantidade de tentativas incorretas observada pelo controlador consultado,
  quando disponivel;
- `whenCreated`, apresentado como data de criacao da conta;
- `accountExpires`, apresentado como data de expiracao somente quando houver
  uma expiracao configurada;
- `pwdLastSet`, apresentado como data da ultima alteracao da senha;
- `info`, apresentado com o rotulo **Notes** somente quando possuir conteudo;
- `DistinguishedName`, ou uma unidade organizacional derivada dele.

`badPasswordTime` e `badPwdCount` nao sao replicados e sao mantidos
separadamente em cada controlador. Portanto:

- a ultima senha incorreta consolidada deve ser o maior `badPasswordTime`
  observado entre todos os controladores;
- o relatorio deve informar qual controlador forneceu esse maior horario;
- `badPwdCount` nao deve ser somado;
- a consolidacao deve apresentar somente o maior contador local observado e o
  controlador que o forneceu;
- os valores individuais devem permanecer apenas na memoria durante a
  consolidacao e nao devem gerar uma tabela detalhada por conta e controlador.

Campos obrigatorios ausentes devem ser apresentados como `Nao informado`, sem
interromper a geracao. Data de expiracao e Notes devem ser omitidos da listagem
quando nao possuirem conteudo. O resultado deve ser ordenado de forma
deterministica por `SamAccountName`, ignorando diferenca entre maiusculas e
minusculas.

Os valores relacionados a bloqueio podem mudar durante a propria execucao e
podem refletir caracteristicas de replicacao do AD. O email deve ser tratado
como uma sequencia de fotografias, exibindo claramente data, hora e controlador
de cada consulta.

## Conteudo do email

### Assunto

Usar assunto curto, em portugues e sem dados fornecidos diretamente pelo AD,
por exemplo:

```text
PS Panel - Contas bloqueadas no AD (3)
```

Quando nao houver contas:

```text
PS Panel - Nenhuma conta bloqueada no AD
```

### Corpo HTML

O email deve conter:

- titulo **Contas bloqueadas no Active Directory**;
- total de contas encontradas;
- dominio consultado;
- PDC Emulator identificado;
- quantidade e inventario dos controladores consultados;
- data e hora local da coleta;
- aviso de que o resultado representa o estado observado naquele instante;
- listagem consolidada com um cartao ou bloco vertical por conta, evitando uma
  tabela horizontal larga;
- identificacao, estado, ciclo da conta, ocorrencias de senha incorreta e Notes
  quando houver conteudo;
- identificacao do sistema `PS Panel`;
- nome da rotina executada;
- data e hora do envio.

Todos os textos apresentados no corpo do email devem usar acentuacao correta em
portugues. A implementacao pode usar caracteres Unicode ou entidades HTML,
desde que o cliente de email renderize o texto acentuado corretamente em UTF-8.

Quando nenhuma conta estiver bloqueada, enviar o email normalmente com uma
mensagem de estado vazio clara. Nao omitir o envio e nao gerar uma tabela com
linha ficticia.

O HTML deve usar estilos inline simples para funcionar nos clientes de email
comuns. A legibilidade do relatorio nao deve depender de JavaScript, CSS
externo, imagem remota ou recurso hospedado pelo PS Panel.

## Seguranca e privacidade

- Escapar com HTML encoding todo valor originado do AD antes de inclui-lo no
  corpo HTML.
- Nao inserir valores do AD diretamente em tags, atributos ou estilos.
- Nao registrar o corpo HTML completo em `stdout` ou `stderr`.
- Nao imprimir credenciais, configuracao SMTP, conteudo de
  `database/email-settings.json`, tokens ou segredos.
- Nao receber senha do AD nem senha SMTP por parametro, pois os parametros de
  execucao podem aparecer no historico do PS Panel e na linha de comando.
- Nao desbloquear, habilitar, desabilitar ou modificar contas.
- Nao alterar senha, atributos, grupos ou politicas do AD.
- Nao ignorar erros de certificado TLS no envio de email.
- Nao usar `Send-MailMessage` nem `System.Net.Mail.SmtpClient`.
- Usar exclusivamente `Send-PSPanelEmail` para o transporte SMTP.
- Evitar expor informacoes adicionais sem necessidade, como telefone,
  endereco, grupos, descricao, SID ou dados completos de auditoria.
- Considerar que o relatorio contem dados administrativos sensiveis; os
  destinatarios devem ser obrigatorios e explicitamente informados.

## Tratamento de erros e codigo de saida

Usar erros terminantes nas etapas criticas e um fluxo principal com
`try/catch`.

Devem encerrar a execucao com codigo diferente de zero:

- parametro de destinatario ausente ou invalido;
- modulo `ActiveDirectory` ausente ou impossivel de importar;
- falha ao descobrir o dominio ou o PDC Emulator;
- falha ao enumerar os controladores do dominio;
- falha de autenticacao ou autorizacao na consulta ao AD;
- indisponibilidade de qualquer controlador consultado;
- consulta incompleta ou erro ao carregar dados necessarios;
- modulo `PSPanel.Email` ausente ou impossivel de importar;
- configuracao SMTP ausente ou invalida;
- falha de DNS, conexao, autenticacao, TLS ou envio SMTP.

Uma falha de consulta nao deve resultar no envio de um email dizendo que nao ha
contas bloqueadas. Estado vazio so pode ser informado quando a consulta for
concluida com sucesso.

As mensagens de erro devem:

- ser claras e em portugues;
- identificar a etapa geral que falhou;
- evitar stack trace por padrao;
- evitar despejar objetos completos do AD;
- nunca incluir credenciais ou o corpo do email.

Em caso de sucesso, escrever em `stdout` apenas um resumo operacional, contendo
o dominio, o PDC Emulator, a quantidade de controladores consultados, a
quantidade encontrada e a confirmacao do envio. Nao listar todos os usuarios no
console.

## Fluxo esperado

```text
validar MailTo
  -> importar ActiveDirectory
  -> descobrir dominio, PDC Emulator e todos os controladores
  -> consultar contas bloqueadas em cada controlador
  -> unir as contas pelo DistinguishedName
  -> consultar os atributos locais de cada conta em cada controlador
  -> consolidar o maior badPasswordTime e o maior badPwdCount local
  -> ordenar e montar o inventario de DCs e a visao consolidada
  -> importar PSPanel.Email pelo caminho relativo ao script
  -> enviar um unico email
  -> imprimir resumo seguro
  -> encerrar com codigo 0
```

Qualquer falha anterior ao envio deve interromper o fluxo. Uma falha no envio
tambem deve resultar em codigo diferente de zero para que o historico e os
agendamentos do PS Panel sinalizem o problema.

## Integracao com o PS Panel

O script deve permanecer dentro de `scripts-ps/` para ser descoberto e
executado pelos fluxos existentes.

Nao criar rota, controller, view, model, tabela SQLite ou worker novo nesta
task. O agendamento, quando desejado, deve usar a funcionalidade existente do PS
Panel e informar `-MailTo` nos parametros.

Como o parser atual de parametros do painel separa valores por espacos simples,
documentar o uso de uma lista de emails sem espacos, separada por ponto e
virgula, por exemplo:

```text
-MailTo seguranca@exemplo.local;suporte@exemplo.local
```

Nao alterar o parser global de parametros como parte desta task.

## Fora de escopo

- Desbloquear contas automaticamente.
- Enviar um email separado por usuario.
- Monitorar eventos em tempo real.
- Consultar eventos de seguranca dos controladores de dominio.
- Identificar a estacao ou o processo que provocou o bloqueio.
- Consultar senha expirada ou proxima de expirar.
- Consultar contas de computador bloqueadas.
- Consultar todos os dominios de uma floresta.
- Permitir filtro arbitrario por OU ou LDAP.
- Persistir o resultado em SQLite.
- Criar dashboard, rota ou tela para o relatorio.
- Alterar a configuracao SMTP compartilhada.
- Alterar `PSPanel.Email.psm1`, salvo se a implementacao revelar um defeito
  reproduzivel que impeça o uso documentado; nesse caso, interromper e
  documentar a necessidade antes de ampliar o escopo.
- Atualizar dependencias, DLLs, `package-lock.json` ou modulos externos.
- Alterar o parser de parametros dos scripts.

## Arquivos provaveis

```text
scripts-ps/Relatorio-ContasAD-Bloqueadas.ps1
src/config/release.js
```

O modulo abaixo deve ser apenas consumido:

```text
scripts-ps/modules/PSPanel.Email/PSPanel.Email.psm1
```

## Criterios de aceite

- O arquivo `scripts-ps/Relatorio-ContasAD-Bloqueadas.ps1` existe e pode ser
  descoberto pelo PS Panel.
- O script exige `-MailTo` e nao possui destinatario organizacional real
  codificado.
- O script nao recebe credenciais do AD ou SMTP por parametro.
- O modulo `ActiveDirectory` e importado explicitamente e nao e instalado em
  runtime.
- O dominio atual, o PDC Emulator e todos os controladores sao descobertos antes
  da consulta.
- Cada consulta usa explicitamente em `-Server` o controlador correspondente.
- A busca usa o estado `LockedOut`, e repetida em todos os controladores e
  retorna somente contas de usuario.
- A uniao das buscas nao duplica uma conta presente em varios controladores.
- Contas desabilitadas que tambem estejam bloqueadas aparecem no resultado com
  seu estado identificado.
- Senhas expiradas ou configuradas para nunca expirar nao entram no relatorio
  apenas por essas condicoes.
- O resultado e ordenado por `SamAccountName`.
- O email apresenta total, dominio, PDC Emulator, todos os controladores e
  horarios da coleta.
- O email possui uma visao consolidada por conta.
- A visao consolidada usa cartoes ou blocos verticais por conta e nao uma tabela
  horizontal larga.
- O email nao possui a secao **Detalhamento por controlador** nem uma linha por
  combinacao de conta e controlador.
- Os textos visiveis do email possuem acentuacao correta em portugues.
- Cada conta apresenta data de criacao e data da ultima alteracao da senha.
- A data de expiracao aparece somente quando a conta possui expiracao
  configurada.
- Notes aparece somente quando o atributo `info` possui conteudo.
- A ultima senha incorreta consolidada e o maior `badPasswordTime` observado.
- O controlador que forneceu a ultima senha incorreta e identificado.
- `badPwdCount` nao e somado; o maior valor local e exibido com seu controlador.
- Cada registro apresenta os campos definidos nesta task ou o fallback
  `Nao informado`.
- Todos os valores vindos do AD recebem HTML encoding.
- Nenhuma conta bloqueada resulta em email de estado vazio, e nao em ausencia
  silenciosa de envio.
- Falha na consulta nao e apresentada como resultado vazio.
- Um unico email e enviado por execucao bem-sucedida.
- O envio usa `Send-PSPanelEmail`.
- O script nao usa `Send-MailMessage` nem `System.Net.Mail.SmtpClient`.
- A configuracao e as credenciais SMTP nao sao duplicadas no script.
- O console apresenta somente um resumo seguro e nao lista todas as contas.
- Falha de consulta ou envio encerra com codigo diferente de zero.
- O script nao modifica qualquer objeto do AD.
- O release da aplicacao e incrementado quando a task for implementada.

## Testes sugeridos

1. Validar o parse do arquivo PowerShell sem executar a consulta.
2. Executar sem `-MailTo` e confirmar falha de validacao antes de acessar o AD.
3. Executar em host sem o modulo `ActiveDirectory` e confirmar mensagem clara e
   codigo diferente de zero.
4. Executar com uma identidade sem permissao de leitura e confirmar que nenhum
   email de estado vazio e enviado.
5. Tornar um dos controladores indisponivel e confirmar falha, sem envio de
   consolidacao parcial apresentada como completa.
6. Em ambiente de homologacao, bloquear uma conta de usuario habilitada e
   confirmar sua presenca no relatorio.
7. Bloquear uma conta de teste desabilitada e confirmar que ela aparece com
   `Enabled` igual a falso.
8. Manter uma conta apenas com senha expirada e confirmar que ela nao aparece
   sem estar bloqueada.
9. Validar uma execucao sem contas bloqueadas e confirmar o recebimento do
   email de estado vazio.
10. Usar dois destinatarios separados por ponto e virgula e confirmar o
    recebimento por ambos.
11. Inserir, em atributos de uma conta de teste, caracteres como `&`, `<`, `>`,
    aspas e texto semelhante a HTML; confirmar que aparecem como texto e nao
    sao interpretados pelo cliente de email.
12. Simular configuracao SMTP ausente ou invalida e confirmar codigo diferente
    de zero sem exposicao de senha.
13. Simular falha SMTP e confirmar que o historico do PS Panel registra a
    execucao como erro.
14. Inspecionar `stdout`, `stderr` e o historico para confirmar que nao contem
    credenciais, configuracao SMTP, corpo HTML ou lista completa de usuarios.
15. Executar pelo fluxo manual e por um agendamento do PS Panel usando uma lista
    de destinatarios sem espacos.
16. Produzir tentativas de senha incorreta contra controladores diferentes e
    confirmar que os valores consolidados consideram todos eles.
17. Confirmar que a visao consolidada seleciona o horario mais recente e
    identifica o controlador correspondente.
18. Configurar contadores locais diferentes e confirmar que o relatorio mostra
    o maior valor sem soma-los.
19. Validar uma conta com e outra sem expiracao e confirmar que o campo aparece
    somente na primeira.
20. Validar uma conta com e outra sem `info` e confirmar que Notes aparece
    somente quando preenchido.
21. Inserir quebras de linha e caracteres semelhantes a HTML em Notes e
    confirmar que o texto e escapado e preserva a separacao visual das linhas.
22. Confirmar a exibicao correta de acentos em titulos, rotulos e mensagens nos
    clientes de email usados pela equipe.

Todos os testes de AD e SMTP devem ser realizados apenas em ambiente autorizado
e com contas de homologacao apropriadas. Nao imprimir nem documentar valores
reais do `.env` ou de `database/email-settings.json`.

## Validacao esperada na implementacao

Validar a sintaxe sem executar o script:

```powershell
powershell.exe -NoProfile -Command "$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\scripts-ps\Relatorio-ContasAD-Bloqueadas.ps1'), [ref]$null, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }"
```

Validar o arquivo de release alterado:

```powershell
node --check src\config\release.js
```

Quando houver acesso autorizado a um dominio e SMTP de homologacao, executar os
testes funcionais sugeridos. A validacao nao deve iniciar nem reutilizar
servidor web na porta `3000`.

---

## Assinatura da LLM

- Data: 23/07/2026 14:58
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 23/07/2026 15:15
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 23/07/2026 15:29
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 24/07/2026 10:10
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao
