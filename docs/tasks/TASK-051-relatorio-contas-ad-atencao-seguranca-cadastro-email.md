# TASK-051 - Criar relatorio por email de contas do AD que merecem atencao

## Contexto

O PS Panel ja possui:

- o modulo compartilhado `scripts-ps/modules/PSPanel.Email/PSPanel.Email.psm1`,
  que exporta `Send-PSPanelEmail`;
- o script `scripts-ps/Relatorio-ContasAD-Bloqueadas.ps1`, voltado
  especificamente ao estado atual de bloqueio de contas;
- suporte para executar e agendar scripts PowerShell existentes em
  `scripts-ps/`.

Falta um relatorio preventivo e cadastral que identifique contas de usuario do
Active Directory que merecem revisao por configuracao insegura, inatividade,
privilegios residuais ou dados de cadastro incompletos.

O novo relatorio deve ser somente informativo. Ele nao pode modificar contas,
senhas, grupos, atributos ou politicas do AD.

## Objetivo

Criar um script PowerShell executavel pelo PS Panel que:

1. consulte as contas de usuario do dominio Active Directory atual;
2. avalie o conjunto inicial de criterios de seguranca e qualidade cadastral
   definido nesta task;
3. consolide varias ocorrencias da mesma conta em um unico registro;
4. classifique cada ocorrencia por categoria e severidade;
5. gere um relatorio HTML seguro, legivel e ordenado;
6. envie um unico email por execucao usando `Send-PSPanelEmail`;
7. envie tambem um email de estado satisfatorio quando nenhuma ocorrencia for
   encontrada;
8. encerre com codigo diferente de zero se a coleta, avaliacao ou o envio
   falhar.

## Importante

Esta atualizacao da task deve ser apenas especificada neste momento. Nao
adequar automaticamente o script existente sem nova solicitacao ou confirmacao
do usuario.

## Arquivo proposto

```text
scripts-ps/Relatorio-ContasAD-Atencao.ps1
```

Ao concluir a implementacao, atualizar tambem:

```text
src/config/release.js
```

usando a data local da implementacao e o proximo sequencial global no formato
`vAAAA.MM.DD-NNN`, conforme `AGENTS.md`.

## Dependencias e ambiente

O script deve:

- executar em Windows sob uma identidade de dominio com permissao de leitura
  sobre usuarios e grupos consultados;
- exigir o modulo Microsoft `ActiveDirectory`, normalmente fornecido por RSAT
  ou Windows Server;
- importar `ActiveDirectory` explicitamente com erro terminante;
- nao instalar RSAT, modulos ou dependencias em tempo de execucao;
- usar a identidade do processo, sem receber usuario ou senha do AD;
- descobrir o dominio atual com `Get-ADDomain`;
- usar explicitamente o PDC Emulator do dominio como servidor da consulta;
- importar `PSPanel.Email.psm1` por caminho baseado em `$PSScriptRoot`;
- usar somente a configuracao SMTP compartilhada em
  `database/email-settings.json`, lida internamente pelo modulo de email.

Os atributos usados nesta task sao replicados ou representam configuracoes do
objeto. Nao e necessario consultar todos os controladores de dominio como no
relatorio de contas bloqueadas. O campo `LastLogonDate`, derivado de
`lastLogonTimestamp`, e aproximado e deve ser apresentado como tal.

## Parametros

### Destinatarios

Definir um parametro obrigatorio:

```text
-MailTo
```

Ele deve aceitar um ou mais enderecos em uma unica string, separados por
virgula ou ponto e virgula, conforme suportado por `Send-PSPanelEmail`.

Nao codificar endereco organizacional real no script. A ausencia de
destinatario deve falhar antes da consulta ao AD.

Exemplos:

```powershell
.\scripts-ps\Relatorio-ContasAD-Atencao.ps1 -MailTo 'seguranca@exemplo.local'
.\scripts-ps\Relatorio-ContasAD-Atencao.ps1 -MailTo 'seguranca@exemplo.local;rh@exemplo.local'
```

### Limiares

Oferecer parametros opcionais, com validacao de faixa:

```text
-InactiveDays 90
-PrivilegedInactiveDays 30
-PasswordAgeDays 365
-NeverLoggedGraceDays 15
```

Regras:

- aceitar somente inteiros positivos;
- aplicar limites superiores razoaveis para evitar erro de digitacao;
- registrar no cabecalho do email os valores efetivamente usados;
- nao receber expressoes, filtros LDAP ou comandos arbitrarios;
- manter os valores padrao acima quando o parametro for omitido.

### Tipos de conta

Os tipos nao devem ser recebidos por parametro. O cadastro corporativo passa a
adotar um vocabulario fixo no atributo `employeeType`:

```text
Service
Funcionario
Estagiario
Terceirizado
```

A comparacao deve ignorar maiusculas, minusculas e espacos externos, mas o
relatorio deve apresentar os nomes canonicos acima.

Valores vazios ou diferentes desse conjunto devem ser classificados como
**Sem tipo definido** e gerar uma ocorrencia cadastral explicita. Nao inferir o
tipo oficial pelo nome da conta, email, OU, `Description`, SPN ou grupo.

### Parametros fora do escopo

Nao adicionar:

- credenciais do AD ou SMTP;
- host, porta, remetente ou opcoes TLS;
- `SearchBase`, filtro LDAP ou script block fornecido pelo usuario;
- opcao para corrigir, habilitar, desabilitar ou excluir contas;
- opcao para alterar senhas ou grupos;
- opcao para ignorar validacao de certificado;
- instalacao automatica do modulo `ActiveDirectory`.

A primeira versao deve consultar todo o dominio atual.

## Escopo das contas

A consulta base deve carregar objetos da classe `user` do dominio atual e
ignorar objetos de computador.

As regras de seguranca devem avaliar contas habilitadas, exceto quando o
criterio disser explicitamente que se aplica a conta desabilitada.

O atributo `employeeType` deve ser a fonte oficial do tipo principal:

1. **Service**: conta tecnica usada por servico, aplicacao, integracao ou
   automacao;
2. **Funcionario**: pessoa com vinculo empregaticio comum;
3. **Estagiario**: pessoa com vinculo de estagio e duracao limitada;
4. **Terceirizado**: pessoa externa ou prestador com duracao contratual;
5. **Sem tipo definido**: `employeeType` vazio ou diferente dos quatro valores
   permitidos.

`ServicePrincipalName` deve permanecer como indicador tecnico, nao como fonte
oficial da classificacao. Uma conta `Service` pode legitimamente nao possuir
SPN, por exemplo em tarefas agendadas, scripts ou integracoes que nao usam
Kerberos. Por outro lado, uma conta com SPN cujo `employeeType` nao seja
`Service` deve ser sinalizada para revisao de classificacao.

O marcador **Privilegiada** e independente do tipo principal. Qualquer conta
pode acumular esse marcador quando pertencer direta ou indiretamente aos
grupos privilegiados definidos nesta task.

As regras cadastrais devem usar o seguinte perfil:

| Tipo | Campos obrigatorios | Regras adicionais |
| --- | --- | --- |
| `Service` | `Description` | senha de servico e coerencia com SPN |
| `Funcionario` | `Description`, `employeeID`, `Department`, `Title`, `Manager` | gestor valido e ativo |
| `Estagiario` | `Description`, `employeeID`, `Department`, `Title`, `Manager` | gestor valido e ativo; expiracao obrigatoria |
| `Terceirizado` | `Description`, `employeeID`, `Company`, `Department`, `Title`, `Manager` | gestor valido e ativo; expiracao obrigatoria |
| Sem tipo definido | `Description`, `employeeID`, `Department`, `Title`, `Manager` | ocorrencia de tipo ausente ou invalido |

Contas `Service` nao devem ser cobradas por `employeeID`, `Company`,
`Department`, `Title` ou `Manager`. O `Description` deve identificar ao menos
o sistema, finalidade ou responsavel operacional. O relatorio apenas aponta
ausencia; ele nao deve interpretar texto livre para decidir se a descricao e
suficiente.

## Atributos necessarios

Solicitar somente os atributos necessarios, incluindo:

```text
SamAccountName
DisplayName
UserPrincipalName
mail
Enabled
Description
employeeID
employeeType
Company
Department
Title
Manager
whenCreated
PasswordLastSet
LastLogonDate
PasswordNeverExpires
PasswordNotRequired
DoesNotRequirePreAuth
AccountExpirationDate
ServicePrincipalName
MemberOf
DistinguishedName
```

Podem ser solicitados atributos tecnicos adicionais estritamente necessarios
para resolver grupos aninhados, SID, dominio ou unidade organizacional.

Nao coletar telefone, endereco residencial, dados pessoais sem uso no
relatorio, hashes, credenciais ou eventos de autenticacao.

## Grupos privilegiados

Resolver grupos privilegiados por SID conhecido sempre que possivel, evitando
dependencia do idioma do dominio. O conjunto inicial deve abranger:

- Administrators;
- Domain Admins;
- Enterprise Admins;
- Schema Admins;
- Account Operators;
- Server Operators;
- Backup Operators;
- Print Operators;
- Group Policy Creator Owners;
- DnsAdmins, quando existir no dominio.

A avaliacao deve considerar associacao direta e indireta. Nao basta examinar
somente a lista textual de `MemberOf` do usuario.

Para grupos do container `Builtin` e grupos especificos do dominio ou da
floresta, resolver os objetos no contexto correto. Grupo inexistente deve ser
registrado como nao aplicavel, mas falha ao consultar um grupo existente ou
resolver sua associacao deve interromper a execucao para evitar resultado
parcial enganoso.

O relatorio deve mostrar os grupos privilegiados que justificaram a
classificacao, usando nomes escapados para HTML.

## Criterios da primeira versao

Cada ocorrencia deve possuir codigo estavel, categoria, severidade, evidencia e
acao recomendada. Os codigos nao devem depender do texto visivel.

### Aplicacao geral e por tipo

As seguintes regras sao gerais e independem do tipo principal:

- `SEC-001` a `SEC-009`;
- `CAD-002`, quando houver `Manager`;
- `CAD-003`;
- `CAD-005`.

As seguintes regras dependem do tipo:

- `SEC-010`: somente `Service`;
- `CAD-001`: campos obrigatorios conforme a matriz de tipos;
- `CAD-004`: somente `Estagiario` e `Terceirizado`;
- `CAD-006`: coerencia entre `employeeType` e a presenca de SPN.

Contas sem tipo definido continuam recebendo todas as regras gerais. Para
`CAD-001`, elas usam provisoriamente o perfil cadastral de pessoa definido na
matriz, alem de receberem `CAD-005`.

### Regras de seguranca

#### SEC-001 - Conta habilitada inativa

- Severidade: alta.
- Condicao: `Enabled = True`, existe `LastLogonDate` e a data e anterior ao
  limite definido por `InactiveDays`.
- Evidencia: data aproximada do ultimo logon e quantidade de dias.
- Acao: validar vinculo e necessidade; desabilitar pelo processo oficial se
  confirmado desuso.

#### SEC-002 - Conta habilitada que nunca realizou logon

- Severidade: alta.
- Condicao: `Enabled = True`, `LastLogonDate` ausente e `whenCreated` anterior
  ao periodo de tolerancia `NeverLoggedGraceDays`.
- Evidencia: data de criacao e dias desde a criacao.
- Contas mais novas que a tolerancia nao devem ser sinalizadas.

#### SEC-003 - Senha antiga

- Severidade: alta.
- Condicao: conta habilitada com `PasswordLastSet` anterior ao limite definido
  por `PasswordAgeDays`.
- Se `PasswordLastSet` estiver ausente ou representar senha nunca definida,
  registrar a evidencia explicitamente, sem inventar uma data.
- A ocorrencia e indicativa e nao autoriza troca automatica de senha.

#### SEC-004 - Senha configurada para nunca expirar

- Severidade: alta.
- Condicao: conta habilitada com `PasswordNeverExpires = True`.
- Contas de servico tambem devem aparecer; a classificacao deve permitir uma
  revisao separada.

#### SEC-005 - Senha nao exigida

- Severidade: critica.
- Condicao: conta habilitada com `PasswordNotRequired = True`.

#### SEC-006 - Pre-autenticacao Kerberos desabilitada

- Severidade: critica.
- Condicao: conta habilitada com `DoesNotRequirePreAuth = True`.

#### SEC-007 - Conta expirada ainda habilitada

- Severidade: alta.
- Condicao: `Enabled = True` e `AccountExpirationDate` anterior ao momento da
  coleta.
- Nao confundir expiracao da conta com expiracao de senha.

#### SEC-008 - Conta privilegiada inativa

- Severidade: critica.
- Condicao: conta classificada como privilegiada e:
  - ultimo logon anterior a `PrivilegedInactiveDays`; ou
  - nunca realizou logon e ja ultrapassou `NeverLoggedGraceDays`.
- Evidencia: grupos privilegiados, ultimo logon aproximado e dias.

Uma conta pode receber simultaneamente `SEC-001` e `SEC-008`. O email deve
consolidar as duas ocorrencias sem duplicar a conta.

#### SEC-009 - Conta desabilitada ainda privilegiada

- Severidade: alta.
- Condicao: `Enabled = False` e associacao direta ou indireta a qualquer grupo
  privilegiado.
- Esta e a unica regra inicial que inclui deliberadamente contas
  desabilitadas.

#### SEC-010 - Conta de servico com senha antiga

- Severidade: alta.
- Condicao: conta habilitada com `employeeType = Service` e:
  - senha anterior a `PasswordAgeDays`; ou
  - `PasswordNeverExpires = True`; ou
  - `PasswordLastSet` ausente.
- A presenca de SPN nao e obrigatoria para aplicar esta regra.
- Evidencia: tipo cadastrado, idade da senha, flags relevantes e quantidade de
  SPNs quando houver.
- Nao incluir o valor completo dos SPNs no email; informar apenas a quantidade
  para reduzir exposicao.
- Acao recomendada: revisar uso, privilegios e viabilidade de conta gerenciada,
  como gMSA, sem migracao automatica.

### Regras de qualidade cadastral

#### CAD-001 - Campos obrigatorios ausentes

- Severidade: media.
- Para contas habilitadas `Funcionario`, `Estagiario` ou sem tipo definido,
  verificar separadamente:
  - `Description`;
  - `employeeID`;
  - `Department`;
  - `Title`;
  - `Manager`.
- Para contas habilitadas `Terceirizado`, verificar os mesmos campos e tambem
  `Company`.
- Considerar ausente o valor nulo, vazio ou composto somente por espacos.
- A evidencia deve listar exatamente os campos ausentes.
- Para contas `Service`, exigir somente `Description` neste criterio.

#### CAD-002 - Gestor inexistente ou desabilitado

- Severidade: alta quando o gestor esta desabilitado e media quando a
  referencia e invalida.
- Condicao:
  - `Manager` possui DN que nao pode ser resolvido como usuario; ou
  - o usuario apontado por `Manager` possui `Enabled = False`.
- Gestor simplesmente ausente deve permanecer em `CAD-001`, sem gerar
  `CAD-002` adicional.

#### CAD-003 - Identificador ou endereco duplicado

- Severidade: alta.
- Comparar entre todos os usuarios carregados:
  - `mail`;
  - `UserPrincipalName`;
  - `employeeID`.
- Ignorar maiusculas, minusculas e espacos externos.
- Valores vazios nao participam da deteccao de duplicidade.
- Cada conta envolvida deve receber a ocorrencia, indicando o campo duplicado e
  a quantidade de objetos com o mesmo valor.
- Para reduzir exposicao, o email nao deve listar o valor completo duplicado
  quando ele for email ou UPN; pode mascarar parcialmente o valor.

#### CAD-004 - Conta temporaria sem data de expiracao

- Severidade: alta.
- Condicao: conta habilitada com `employeeType = Estagiario` ou
  `employeeType = Terceirizado` e `AccountExpirationDate` ausente.
- A evidencia deve informar o tipo e que nao existe data de expiracao.
- Nao inferir vinculo temporario por nome, OU, email ou outra heuristica.

#### CAD-005 - Conta sem tipo ou responsavel identificado

- Severidade: media.
- Condicao de tipo:
  - `employeeType` vazio caracteriza tipo ausente; ou
  - valor diferente de `Service`, `Funcionario`, `Estagiario` e
    `Terceirizado` caracteriza tipo invalido.
- Para `Funcionario`, `Estagiario`, `Terceirizado` e contas sem tipo definido,
  `Manager` vazio caracteriza responsavel ausente.
- Para `Service`, `Description` vazia caracteriza responsavel ou contexto
  operacional ausente.
- A evidencia deve diferenciar tipo ausente, tipo invalido e responsavel
  ausente.
- Quando houver um valor invalido, apresenta-lo com HTML encoding.
- Este criterio pode coexistir com `CAD-001`, mas deve aparecer como uma unica
  ocorrencia adicional por conta, e nao como varias linhas duplicadas.

#### CAD-006 - Classificacao incompativel com SPN

- Severidade: media.
- Condicao: a conta possui ao menos um `ServicePrincipalName`, mas seu
  `employeeType` e `Funcionario`, `Estagiario`, `Terceirizado`, vazio ou
  invalido.
- A evidencia deve informar o tipo cadastrado e somente a quantidade de SPNs.
- Nao incluir os valores completos dos SPNs.
- A ausencia de SPN em uma conta `Service` nao gera ocorrencia.
- Acao recomendada: confirmar a finalidade da conta e corrigir
  `employeeType` somente se ela for de fato uma conta de servico.

## Avaliacao e consolidacao

- Capturar um unico horario de referencia no inicio e usa-lo em todos os
  calculos de idade.
- Calcular dias completos de forma consistente.
- Normalizar textos apenas para comparacao; preservar o valor original para
  apresentacao.
- Nunca tratar falha de conversao de data como ausencia silenciosa.
- Manter uma colecao por `DistinguishedName` ou `ObjectGUID`.
- Uma conta deve aparecer uma unica vez no detalhamento, contendo todas as suas
  ocorrencias ordenadas por severidade e codigo.
- Ordenar contas por maior severidade e depois por `SamAccountName`, ignorando
  diferenca entre maiusculas e minusculas.
- Produzir totais de contas afetadas e de ocorrencias; esses numeros sao
  diferentes e devem ser rotulados corretamente.
- Produzir totais por categoria, severidade e codigo.

Mapeamento de severidade para ordenacao:

```text
critica > alta > media > informativa
```

## Conteudo do email

### Assunto

Quando houver ocorrencias:

```text
PS Panel - Contas do AD que merecem atencao (12)
```

O numero deve representar contas distintas, nao a quantidade total de
ocorrencias.

Quando nao houver ocorrencias:

```text
PS Panel - Nenhuma conta do AD requer atencao
```

### Corpo HTML

O email deve conter:

- titulo `Contas do Active Directory que merecem atencao`;
- dominio e PDC Emulator consultados;
- data e hora local da coleta;
- limiares efetivamente usados;
- aviso de que `LastLogonDate` e aproximado;
- total de usuarios avaliados;
- total de contas afetadas;
- total de ocorrencias;
- resumo das contas avaliadas por tipo principal, incluindo `Sem tipo definido`;
- resumo por severidade;
- resumo por criterio, com descricao das condicoes aplicadas;
- bloco ou cartao por conta afetada;
- identificacao, `employeeType` original, tipo principal normalizado, marcadores,
  estado e unidade organizacional;
- lista das ocorrencias com codigo, severidade, evidencia e acao recomendada;
- identificacao do sistema `PS Panel`;
- nome do script e horario de envio.

Evitar tabela horizontal excessivamente larga. Usar estilos inline simples,
sem JavaScript, CSS externo, imagem remota ou dependencia do PS Panel estar
acessivel pelo destinatario.

Quando nenhuma ocorrencia for encontrada, enviar normalmente um estado vazio
com dominio, horario, quantidade avaliada e limiares. Nao criar linha ficticia
e nao omitir silenciosamente o email.

## Seguranca e privacidade

- Aplicar HTML encoding a todo valor originado do AD.
- Nao inserir valores do AD diretamente em tags, atributos ou estilos.
- Nao imprimir o corpo HTML em `stdout`, `stderr` ou historico.
- Nao imprimir configuracao SMTP, credenciais, tokens ou conteudo de
  `database/email-settings.json`.
- Nao receber segredo em parametro.
- Nao listar SPNs completos.
- Mascarar email ou UPN quando exibidos como evidencia de duplicidade.
- Nao modificar qualquer objeto do AD.
- Nao usar `Send-MailMessage` ou `System.Net.Mail.SmtpClient`.
- Usar exclusivamente `Send-PSPanelEmail`.
- Nao desabilitar validacao de certificado TLS.
- Tratar o relatorio como informacao administrativa sensivel e exigir
  destinatarios explicitos.

## Desempenho

- Evitar uma chamada `Get-ADUser` por usuario quando os dados puderem ser
  carregados na consulta base.
- Criar indices em memoria para DN de usuario, gestor, email, UPN e matricula.
- Resolver associacoes privilegiadas de modo limitado ao conjunto de grupos
  desta task.
- Nao usar consulta LDAP sem limite originada de parametro do usuario.
- Nao gravar cache, CSV temporario ou resultado em SQLite.

## Tratamento de erros

Usar erros terminantes nas etapas criticas e fluxo principal com `try/catch`.

Devem encerrar com codigo diferente de zero:

- destinatario ausente ou invalido;
- limiar fora da faixa aceita;
- modulo `ActiveDirectory` indisponivel;
- falha ao descobrir dominio ou PDC Emulator;
- falha de autenticacao ou autorizacao no AD;
- falha na consulta base;
- falha ao resolver grupos privilegiados ou gestores necessarios;
- avaliacao incompleta;
- modulo `PSPanel.Email` indisponivel;
- configuracao SMTP ausente ou invalida;
- falha de DNS, conexao, autenticacao, TLS ou envio.

Falha de consulta nunca deve gerar email afirmando que nenhuma conta requer
atencao. Resultado vazio so e valido depois que todas as etapas forem
concluidas.

As mensagens devem estar em portugues, identificar a etapa geral e nunca
exibir stack trace, objetos completos do AD, corpo HTML ou segredos por padrao.

Em sucesso, `stdout` deve conter somente resumo operacional: dominio, servidor,
quantidade avaliada, contas afetadas, ocorrencias e confirmacao do envio.

## Fluxo esperado

```text
validar parametros
  -> importar ActiveDirectory
  -> descobrir dominio e PDC Emulator
  -> carregar usuarios e atributos necessarios
  -> resolver grupos privilegiados e associacoes aninhadas
  -> indexar gestores e campos sujeitos a duplicidade
  -> classificar contas por employeeType
  -> marcar valores vazios ou invalidos como Sem tipo definido
  -> aplicar SEC-001 a SEC-010
  -> aplicar CAD-001 a CAD-006
  -> consolidar e ordenar ocorrencias por conta
  -> montar HTML com valores escapados
  -> importar PSPanel.Email
  -> enviar um unico email
  -> imprimir resumo seguro
  -> encerrar com codigo 0
```

## Integracao com o PS Panel

O script deve permanecer em `scripts-ps/` para ser descoberto e executado
pelos fluxos existentes.

Nao criar rota, controller, view, model, tabela SQLite ou worker nesta task.
O agendamento deve usar a funcionalidade existente e informar `-MailTo` e,
quando necessario, os limiares.

Como o parser atual separa parametros por espacos simples, listas de
destinatarios devem ser informadas sem espacos:

```text
-MailTo seguranca@exemplo.local;rh@exemplo.local
```

Nao alterar o parser global de parametros.

## Fora de escopo

- Corrigir automaticamente qualquer ocorrencia.
- Desabilitar, excluir ou mover contas.
- Alterar senha, expiracao, gestor, descricao ou outro atributo.
- Remover membros de grupos.
- Avaliar contas de computador.
- Consultar todos os dominios de uma floresta.
- Consultar eventos de seguranca ou detectar comportamento em tempo real.
- Validar vazamento de senha, complexidade da senha ou conteudo da senha.
- Avaliar MFA ou risco no Microsoft Entra ID.
- Verificar delegacao Kerberos, `SIDHistory` ou algoritmos Kerberos nesta
  primeira versao.
- Criar anexos CSV, dashboard, rota ou tela.
- Persistir historico detalhado do relatorio em SQLite.
- Alterar a configuracao SMTP compartilhada.
- Alterar `PSPanel.Email.psm1`, salvo defeito reproduzivel que impeça seu uso;
  nesse caso, interromper e documentar antes de ampliar o escopo.
- Atualizar dependencias, DLLs ou `package-lock.json`.
- Alterar `Relatorio-ContasAD-Bloqueadas.ps1`.

## Arquivos provaveis

```text
scripts-ps/Relatorio-ContasAD-Atencao.ps1
src/config/release.js
```

O modulo abaixo deve ser apenas consumido:

```text
scripts-ps/modules/PSPanel.Email/PSPanel.Email.psm1
```

## Criterios de aceite

- O novo script existe em `scripts-ps/` e e descoberto pelo PS Panel.
- `-MailTo` e obrigatorio e nao existe destinatario real codificado.
- Os quatro limiares possuem os valores padrao definidos nesta task.
- O script nao recebe credenciais, filtro LDAP ou comando arbitrario.
- O modulo `ActiveDirectory` e importado sem instalacao automatica.
- Dominio e PDC Emulator sao descobertos antes da consulta.
- A coleta solicita somente usuarios e atributos necessarios.
- Contas de computador nao sao avaliadas.
- Grupos privilegiados diretos e aninhados sao considerados.
- Cada regra de `SEC-001` a `SEC-010` possui teste correspondente.
- Cada regra de `CAD-001` a `CAD-006` possui teste correspondente.
- Os unicos tipos reconhecidos sao `Service`, `Funcionario`, `Estagiario` e
  `Terceirizado`.
- A comparacao de tipos ignora caixa e espacos externos.
- `employeeType` vazio ou diferente dos quatro valores e apresentado como
  `Sem tipo definido` e recebe `CAD-005`.
- Contas `Service` sao identificadas pelo `employeeType`, nao pela presenca de
  SPN.
- Contas `Service` sem SPN continuam classificadas como servico.
- Contas `Service` nao sao cobradas por matricula, empresa, departamento, cargo
  ou gestor.
- Contas `Funcionario`, `Estagiario` e `Terceirizado` recebem os campos
  obrigatorios correspondentes da matriz.
- `Estagiario` e `Terceirizado` sem expiracao recebem `CAD-004`.
- Conta com SPN e tipo diferente de `Service` recebe `CAD-006`.
- Duplicidades ignoram caixa e espacos externos.
- Gestor desabilitado ou invalido e identificado sem consulta repetida por
  usuario.
- Uma conta aparece uma unica vez com todas as suas ocorrencias.
- O relatorio diferencia contas afetadas de total de ocorrencias.
- O relatorio apresenta total por tipo, incluindo contas sem tipo definido.
- O email informa severidade, evidencia e acao recomendada.
- Valores do AD recebem HTML encoding.
- Emails e UPNs duplicados sao mascarados na evidencia.
- SPNs completos nao aparecem no email ou console.
- Execucao sem ocorrencias envia email de estado satisfatorio.
- Falha de coleta nao e apresentada como estado satisfatorio.
- Um unico email e enviado por execucao bem-sucedida.
- O envio usa `Send-PSPanelEmail`.
- Nao existe uso de `Send-MailMessage` ou `System.Net.Mail.SmtpClient`.
- O console nao lista usuarios, HTML ou segredos.
- O script nao modifica o AD.
- Falha de coleta, avaliacao ou envio retorna codigo diferente de zero.
- O release e incrementado quando a task for implementada.

## Testes sugeridos

1. Validar o parse do PowerShell sem executar consulta.
2. Executar sem `-MailTo` e confirmar falha anterior ao acesso ao AD.
3. Informar limiares invalidos e confirmar rejeicao.
4. Executar sem `ActiveDirectory` e confirmar erro claro.
5. Executar sem permissao de leitura e confirmar que nao e enviado estado
   satisfatorio.
6. Criar ou usar contas de homologacao para provocar isoladamente cada regra
   `SEC-001` a `SEC-010`.
7. Criar ou usar contas de homologacao para provocar isoladamente cada regra
   `CAD-001` a `CAD-006`.
8. Validar conta nova sem logon dentro e fora da tolerancia de 15 dias.
9. Validar os limites exatos de 90, 30 e 365 dias.
10. Confirmar que conta privilegiada inativa recebe `SEC-008` mesmo quando
    tambem recebe `SEC-001`.
11. Confirmar associacao privilegiada por grupo aninhado.
12. Confirmar que conta desabilitada comum nao entra por inatividade, mas conta
    desabilitada privilegiada recebe `SEC-009`.
13. Criar uma conta de cada tipo permitido e confirmar sua classificacao,
    inclusive com variacoes de caixa e espacos externos.
14. Confirmar que `employeeType` vazio e valor desconhecido aparecem como
    `Sem tipo definido`, com evidencias distintas em `CAD-005`.
15. Confirmar que conta `Service` sem SPN continua classificada como servico e
    nao recebe `CAD-006`.
16. Confirmar que conta com SPN e tipo diferente de `Service` recebe `CAD-006`
    sem expor o valor do SPN.
17. Confirmar que conta `Service` nao recebe ausencia de `employeeID`,
    `Company`, `Department`, `Title` ou `Manager`.
18. Confirmar que conta `Service` com senha antiga, senha sem expiracao ou
    PasswordLastSet ausente recebe `SEC-010`, com ou sem SPN.
19. Validar os campos obrigatorios de `Funcionario`, `Estagiario` e
    `Terceirizado`, incluindo `Company` para terceirizados.
20. Validar `Estagiario` e `Terceirizado` com e sem expiracao e confirmar
    `CAD-004` somente quando aplicavel.
21. Validar gestor habilitado, desabilitado, ausente e DN invalido.
22. Criar duplicidades de email, UPN e matricula com variacoes de caixa e
    espacos; confirmar normalizacao e mascara.
23. Inserir caracteres `&`, `<`, `>`, aspas e texto semelhante a HTML em
    atributos de teste; confirmar exibicao como texto.
24. Confirmar no email os totais por tipo, incluindo `Sem tipo definido`.
25. Executar sem ocorrencias e confirmar email de estado satisfatorio.
26. Simular falha SMTP e confirmar codigo diferente de zero.
27. Inspecionar `stdout`, `stderr` e historico para confirmar ausencia de
    usuarios, SPNs, HTML, credenciais e configuracao SMTP.
28. Executar pelo fluxo manual e por agendamento usando parametros sem espacos.
29. Confirmar acentuacao correta em clientes de email usados pela equipe.
30. Confirmar que nenhum objeto do AD foi alterado.

Todos os testes de AD e SMTP devem ocorrer em ambiente autorizado, usando
contas de homologacao. Nunca imprimir ou documentar valores reais de `.env` ou
`database/email-settings.json`.

## Validacao esperada na implementacao

Validar a sintaxe sem executar o script:

```powershell
powershell.exe -NoProfile -Command "$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\scripts-ps\Relatorio-ContasAD-Atencao.ps1'), [ref]$null, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }"
```

Validar o arquivo de release:

```powershell
node --check src\config\release.js
```

Quando houver acesso autorizado ao AD e SMTP de homologacao, executar os testes
funcionais sugeridos. Nao iniciar nem reutilizar servidor web na porta `3000`.

---

## Assinatura da LLM

- Data: 2026-07-24 11:25:23 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 2026-07-24 19:42:31 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao
