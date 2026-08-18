# Atualização do PS Panel

Use este runbook em atualizações rotineiras quando a estação DEV e a VM de
produção já estiverem preparadas. Para instalar ou corrigir WinRM, Kerberos,
firewall, permissões ou acesso Git, consulte a
[preparação do ambiente](INSTALL.md#15-preparação-para-release-e-implantação-remota).

## 1. Pré-requisitos operacionais

- PowerShell 7, Node.js `v24.18.0`, npm e Git disponíveis na estação DEV.
- Árvore local baseada em `main` e acesso de escrita ao `origin`.
- VM acessível por FQDN com Kerberos e WinRM previamente autorizados.
- VM capaz de executar `git fetch origin` sem prompt com a identidade remota.
- Janela de mudança aprovada e tag no formato `vAAAA.MM.DD-NNN`.

Não use IP, `TrustedHosts` ou CredSSP neste fluxo.

## 2. Preparar a release na estação DEV

Encerre processos locais que estejam usando `node_modules`. Incremente
`src/config/release.js` e execute na raiz do projeto:

```powershell
Set-Location '<RAIZ_LOCAL_DO_PSPANEL>'
$release = node -p "require('./src/config/release').version"

npm test
.\deploy\windows\Test-PSPanelRelease.ps1
git status --short
git diff --check
```

Os testes devem terminar sem falhas. Revise as alterações, publique o commit e
confirme a sincronização:

```powershell
git add <ARQUIVOS_DA_RELEASE>
git commit -m '<MENSAGEM_DA_RELEASE>'
git push origin main
git fetch origin main --tags
git status --short
git rev-parse HEAD
git rev-parse origin/main
```

`git status --short` deve ficar vazio e os dois hashes devem ser iguais. Não há
opção para ignorar os testes.

## 3. Criar e verificar a tag

```powershell
.\deploy\windows\New-PSPanelReleaseTag.ps1 -WhatIf
.\deploy\windows\New-PSPanelReleaseTag.ps1

git tag --list $release
git ls-remote --tags origin "refs/tags/$release"
```

A simulação deve ser aprovada. A tag deve aparecer localmente e no `origin`.

## 4. Testar a conexão com a VM

```powershell
$server = '<FQDN_DO_SERVIDOR>'

Resolve-DnsName $server
Test-NetConnection $server -Port 5985
Test-WSMan $server -Authentication Kerberos
```

Interrompa a mudança se DNS, porta ou WSMan falharem. Corrija o ambiente pelo
`INSTALL.md`; não amplie regras de segurança durante a contingência.

## 5. Simular o deploy remoto

```powershell
$preview = .\deploy\windows\Invoke-PSPanelRemoteDeploy.ps1 `
    -ComputerName $server `
    -Version $release `
    -WhatIf

$preview | Select-Object Status, Version, TargetCommit, ServiceStatus, WorkerState
```

Prossiga somente se `Status` for `SimulacaoAprovada` e a versão e o commit alvo
corresponderem à release publicada.

## 6. Executar o deploy

Dentro da janela aprovada, execute e aceite a única confirmação apresentada:

```powershell
$result = .\deploy\windows\Invoke-PSPanelRemoteDeploy.ps1 `
    -ComputerName $server `
    -Version $release
```

Uma falha continua terminante. Preserve o `TargetObject` do erro e não trate a
execução como sucesso apenas porque um objeto de resultado foi emitido.

## 7. Verificar o resultado

```powershell
$result | Select-Object Status, Version, PreviousCommit, TargetCommit, `
    ActiveCommit, SnapshotPath, ServiceStatus, WorkerState, `
    WorkerLastTaskResult, RemoteHealthCheck, ExternalHealthCheck, RemoteLogFile
```

Confirme:

- `Status` de sucesso e `ActiveCommit` igual a `TargetCommit`;
- serviço `PSPanelWeb` em execução;
- worker habilitado, com resultado `0` ou justificativa operacional;
- health check remoto aprovado e externo aprovado quando configurado;
- login funcionando no endereço corporativo da aplicação.

## 8. Registrar log e snapshot

Registre `RemoteLogFile` e `SnapshotPath` no controle da mudança. Na VM, os
locais padrão são:

```text
C:\Apps\PSPanel\log\deploy
C:\Apps\PSPanel-Backups
```

Não copie credenciais, tokens, conteúdo do `.env` ou outros segredos.

## 9. Rollback manual por snapshot

Se o rollback automático não resolver, escolha o snapshot confirmado e simule:

```powershell
$snapshot = '<ID_DO_SNAPSHOT>'

$rollbackPreview = Invoke-Command -ComputerName $server -Authentication Kerberos `
    -ScriptBlock {
        param($snapshotId)
        Set-Location C:\Apps\PSPanel
        .\deploy\windows\Update-PSPanel.ps1 -Rollback $snapshotId `
            -WhatIf -Confirm:$false
    } -ArgumentList $snapshot
```

Após revisar `SimulacaoAprovada`, execute sem `-WhatIf`:

```powershell
$rollbackResult = Invoke-Command -ComputerName $server -Authentication Kerberos `
    -ScriptBlock {
        param($snapshotId)
        Set-Location C:\Apps\PSPanel
        .\deploy\windows\Update-PSPanel.ps1 -Rollback $snapshotId -Confirm:$false
    } -ArgumentList $snapshot
```

Repita as verificações de serviço, worker, health check, log e snapshot.

## 10. Contingência sem WinRM

Com acesso autorizado ao console ou RDP da VM, use o mesmo atualizador:

```powershell
Set-Location C:\Apps\PSPanel
$release = '<TAG_PUBLICADA>'

.\deploy\windows\Update-PSPanel.ps1 -Version $release -WhatIf
.\deploy\windows\Update-PSPanel.ps1 -Version $release
```

Para rollback local, use `-Rollback '<ID_DO_SNAPSHOT>'`, primeiro com `-WhatIf`.
Não use `git reset`, checkout manual nem cópia direta de arquivos. O atualizador
preserva `.env`, `database`, configuração do serviço, snapshots e logs.

## 11. Checklist de encerramento

- [ ] Testes e validador de release aprovados.
- [ ] `main` limpa, sincronizada e publicada.
- [ ] Tag confirmada no `origin`.
- [ ] Conectividade e simulação remota aprovadas.
- [ ] Deploy executado na janela autorizada.
- [ ] Commit ativo, serviço, worker e health checks conferidos.
- [ ] Log e snapshot registrados sem segredos.
- [ ] Rollback registrado e verificado, quando aplicável.
