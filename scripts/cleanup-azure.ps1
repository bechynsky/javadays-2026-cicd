<#
.SYNOPSIS
    Smaže vše, co demo v Azure vytvořilo (celou resource group) – verze pro PowerShell na Windows.

.DESCRIPTION
    Dělá totéž co scripts/cleanup-azure.sh. Před smazáním se zeptá na potvrzení;
    bez dotazu: -Confirm:$false. Mazání běží na pozadí v Azure.

.PARAMETER ResourceGroup
    Název resource group. Výchozí hodnota: rg-javadays-cicd.

.EXAMPLE
    .\scripts\cleanup-azure.ps1

.EXAMPLE
    .\scripts\cleanup-azure.ps1 -ResourceGroup rg-javadays-cicd -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Position = 0)]
    [string] $ResourceGroup = 'rg-javadays-cicd'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Nenašel jsem Azure CLI (az). Nainstalujte ho a otevřete nový terminál."
}

if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Smazat resource group se vším obsahem')) {
    # stderr z az (varování) nesmí ve Windows PowerShell 5.1 shodit skript
    $ErrorActionPreference = 'Continue'
    az group delete --name $ResourceGroup --yes --no-wait
    if ($LASTEXITCODE -ne 0) {
        throw "Mazání se nepodařilo spustit (návratový kód $LASTEXITCODE)."
    }
    Write-Host "Mazání resource group $ResourceGroup běží na pozadí." -ForegroundColor Green
}
