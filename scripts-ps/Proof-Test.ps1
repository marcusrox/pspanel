<#
.SYNOPSIS
    Script mínimo de verificação do painel PS Panel.

.DESCRIPTION
    Exibe uma mensagem de sucesso na saída padrão. Útil para testar execução remota, permissões
    e integração com o histórico do painel, sem efeitos colaterais no sistema.

.PARAMETER Nenhum
    Este script não declara parâmetros. Execute sem argumentos.

.EXAMPLE
    .\Proof-Test.ps1
#>
Write-Output "Script executado com sucesso!"
