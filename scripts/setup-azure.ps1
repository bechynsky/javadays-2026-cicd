<#
.SYNOPSIS
    Jednorázové propojení GitHubu a Azure bez hesel (OIDC) – verze pro PowerShell na Windows.

.DESCRIPTION
    Dělá totéž co scripts/setup-azure.sh:
      1) vytvoří resource group a user-assigned managed identity
      2) dá identitě roli Contributor jen na tuto resource group
      3) přidá federované přihlášení pro GitHub Actions (prostředí "dev" a pull requesty)
         ve starém i novém (neměnném) formátu subject claimu
      4) uloží do GitHubu proměnné AZURE_* a založí prostředí "dev"
      5) pushne kód do větve main – tím spustí workflow CD (vynecháte přepínačem -NoPush)
         Když složka ještě není git repozitář, založí ho a vytvoří první commit.

    Potřebujete: Azure CLI (přihlášené: az login), GitHub CLI (přihlášené: gh auth login)
    a roli Owner nebo User Access Administrator v subskripci.
    Funguje ve Windows PowerShell 5.1 i v PowerShell 7. Skript lze spustit opakovaně.

.PARAMETER Repo
    GitHub repozitář ve tvaru owner/repo, např. bechynsky/javadays-2026-cicd.

.PARAMETER Location
    Region Azure. Výchozí hodnota: westeurope.

.PARAMETER ResourceGroup
    Název resource group. Výchozí hodnota: rg-javadays-cicd.

.PARAMETER CreateRepo
    Když repozitář na GitHubu ještě neexistuje, založí ho (veřejný a prázdný).

.PARAMETER NoPush
    Na konci nepushne kód do GitHubu (push pak uděláte ručně).

.EXAMPLE
    .\scripts\setup-azure.ps1 -Repo bechynsky/javadays-2026-cicd

.EXAMPLE
    .\scripts\setup-azure.ps1 -Repo bechynsky/javadays-2026-cicd -CreateRepo

.EXAMPLE
    .\scripts\setup-azure.ps1 bechynsky/javadays-2026-cicd westeurope rg-javadays-cicd
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = 'GitHub repozitář ve tvaru owner/repo')]
    [ValidatePattern('^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$')]
    [string] $Repo,

    [Parameter(Position = 1)]
    [string] $Location = 'westeurope',

    [Parameter(Position = 2)]
    [string] $ResourceGroup = 'rg-javadays-cicd',

    [switch] $CreateRepo,

    [switch] $NoPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$IdentityName    = 'id-github-javadays-cicd'
$EnvironmentName = 'dev'
$Issuer          = 'https://token.actions.githubusercontent.com'
$Audience        = 'api://AzureADTokenExchange'

function Write-Step {
    param([string] $Text)
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Invoke-Tool {
    # Spustí az nebo gh a vrátí standardní výstup (oříznutý, bez \r).
    # Windows PowerShell 5.1 se při chybě externího programu sám nezastaví,
    # proto kontrolujeme $LASTEXITCODE. Varování, která az/gh píšou na stderr,
    # se jen zobrazí a skript neshodí.
    # -Quiet: potlačí stderr a při chybě místo výjimky vrátí $null.
    param(
        [Parameter(Mandatory = $true, Position = 0)] [string]   $Tool,
        [Parameter(Mandatory = $true, Position = 1)] [string[]] $Arguments,
        [switch] $Quiet
    )
    $ErrorActionPreference = 'Continue'
    if ($Quiet) {
        $out = & $Tool @Arguments 2>$null
    } else {
        $out = & $Tool @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        if ($Quiet) { return $null }
        throw "Příkaz selhal (návratový kód $LASTEXITCODE): $Tool $($Arguments -join ' ')"
    }
    if ($null -eq $out) { return '' }
    return ($out | Out-String).Trim()
}

function Invoke-Interactive {
    # Spustí příkaz s výstupem přímo do konzole (průběh pushe, přihlášení v prohlížeči).
    # Volejte jako samostatný příkaz, výstup nezachytávejte.
    param(
        [Parameter(Mandatory = $true, Position = 0)] [string]   $Tool,
        [Parameter(Mandatory = $true, Position = 1)] [string[]] $Arguments,
        [string] $Hint = ''
    )
    $ErrorActionPreference = 'Continue'
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Příkaz selhal (návratový kód $LASTEXITCODE): $Tool $($Arguments -join ' ') $Hint"
    }
}

Write-Step 'Kontrola nástrojů a přihlášení'
foreach ($tool in @('az', 'gh', 'git')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Nenašel jsem příkaz '$tool'. Nainstalujte ho (README, Příprava na Windows 11) a otevřete nový terminál."
    }
}
if ($null -eq (Invoke-Tool az @('account', 'show', '-o', 'none') -Quiet)) {
    throw 'Azure CLI není přihlášené. Spusťte: az login'
}
if ($null -eq (Invoke-Tool gh @('auth', 'status') -Quiet)) {
    throw 'GitHub CLI není přihlášené. Spusťte: gh auth login'
}
if (-not $NoPush) {
    # Předpoklady pro push ověříme hned, ať se skript nezastaví až po vytvoření všeho v Azure.
    $gitName  = Invoke-Tool git @('config', 'user.name') -Quiet
    $gitEmail = Invoke-Tool git @('config', 'user.email') -Quiet
    if ([string]::IsNullOrEmpty($gitName) -or [string]::IsNullOrEmpty($gitEmail)) {
        throw 'Git nezná vaše jméno a e-mail. Nastavte: git config --global user.name "Jméno Příjmení" a git config --global user.email "vas@email.cz", pak skript spusťte znovu.'
    }
    # Push souborů v .github/workflows vyžaduje u přihlášení gh oprávnění "workflow".
    $headers = Invoke-Tool gh @('api', 'user', '--include')
    if ($headers -match '(?im)^x-oauth-scopes:[ \t]*(.*)$' -and $Matches[1] -notmatch '\bworkflow\b') {
        throw 'Přihlášení gh nemá oprávnění "workflow", bez kterého GitHub odmítne push pipeline. Spusťte: gh auth refresh -h github.com -s workflow a pak skript znovu.'
    }
}

Write-Step 'Azure kontext'
$SubscriptionId   = Invoke-Tool az @('account', 'show', '--query', 'id', '-o', 'tsv')
$SubscriptionName = Invoke-Tool az @('account', 'show', '--query', 'name', '-o', 'tsv')
$TenantId         = Invoke-Tool az @('account', 'show', '--query', 'tenantId', '-o', 'tsv')
Write-Host "    subskripce: $SubscriptionName ($SubscriptionId)"

Write-Step "GitHub repozitář $Repo"
$Owner, $Name = $Repo.Split('/')
$GhUser = Invoke-Tool gh @('api', 'user', '--jq', '.login')
Write-Host "    přihlášený účet GitHub: $GhUser"
if ($null -eq (Invoke-Tool gh @('api', "repos/$Repo", '--jq', '.id') -Quiet)) {
    if (-not $CreateRepo) {
        throw @"
Repozitář $Repo na GitHubu nevidím: buď ještě neexistuje, nebo k němu účet $GhUser nemá přístup.
Založte ho:            gh repo create $Repo --public
nebo spusťte skript s přepínačem -CreateRepo, který ho založí sám.
"@
    }
    Write-Host '    repozitář neexistuje, zakládám ho (veřejný, prázdný)'
    Invoke-Tool gh @('repo', 'create', $Repo, '--public', '--description', 'JavaDays 2026 - CI/CD demo') | Out-Null
}
$OwnerId = Invoke-Tool gh @('api', "repos/$Repo", '--jq', '.owner.id')
$RepoId  = Invoke-Tool gh @('api', "repos/$Repo", '--jq', '.id')
Write-Host "    ID vlastníka: $OwnerId, ID repozitáře: $RepoId"

Write-Step "Resource group $ResourceGroup ($Location)"
# Po smazání běží mazání resource group ještě několik minut na pozadí – počkáme na jeho konec.
$rgStateArgs = @('group', 'show', '--name', $ResourceGroup, '--query', 'properties.provisioningState', '-o', 'tsv')
$rgState = Invoke-Tool az $rgStateArgs -Quiet
$waited = 0
while ($rgState -eq 'Deleting') {
    if ($waited -ge 900) {
        throw "Resource group $ResourceGroup se pořád maže. Zkuste skript spustit znovu za pár minut."
    }
    Write-Host "    resource group se ještě maže, čekám… ($waited s)"
    Start-Sleep -Seconds 15
    $waited += 15
    $rgState = Invoke-Tool az $rgStateArgs -Quiet
}
Invoke-Tool az @('group', 'create', '--name', $ResourceGroup, '--location', $Location,
    '--tags', 'project=javadays-2026-cicd', '-o', 'none') | Out-Null
$RgId = Invoke-Tool az @('group', 'show', '--name', $ResourceGroup, '--query', 'id', '-o', 'tsv')

Write-Step "Managed identity $IdentityName"
Invoke-Tool az @('identity', 'create', '--resource-group', $ResourceGroup, '--name', $IdentityName,
    '-o', 'none') | Out-Null
$ClientId    = Invoke-Tool az @('identity', 'show', '-g', $ResourceGroup, '-n', $IdentityName,
    '--query', 'clientId', '-o', 'tsv')
$PrincipalId = Invoke-Tool az @('identity', 'show', '-g', $ResourceGroup, '-n', $IdentityName,
    '--query', 'principalId', '-o', 'tsv')

Write-Step 'Role Contributor na resource group'
# Při opakovaném spuštění už role existuje – az by na ni hlásil chybu.
$assignedIds = Invoke-Tool az @('role', 'assignment', 'list', '--scope', $RgId, '--role', 'Contributor',
    '--query', '[].principalId', '-o', 'tsv')
$assigned = ($assignedIds -split '\s+') -contains $PrincipalId
if ($assigned) { Write-Host '    role už je přiřazená' }
for ($attempt = 1; -not $assigned -and $attempt -le 6; $attempt++) {
    $result = Invoke-Tool az @('role', 'assignment', 'create',
        '--assignee-object-id', $PrincipalId,
        '--assignee-principal-type', 'ServicePrincipal',
        '--role', 'Contributor',
        '--scope', $RgId,
        '-o', 'none') -Quiet
    if ($null -ne $result) {
        $assigned = $true
        break
    }
    Write-Host "    identita se ještě propisuje, zkusím znovu za 10 s ($attempt/6)"
    Start-Sleep -Seconds 10
}
if (-not $assigned) {
    throw 'Roli se nepodařilo přiřadit. Máte v subskripci roli Owner nebo User Access Administrator?'
}

Write-Step 'Federované přihlášení pro GitHub Actions'
# Repozitáře založené po 15. 7. 2026 posílají neměnný subject s ID vlastníka a repozitáře,
# starší repozitáře původní formát. Zakládáme oba, ať to funguje vždy.
$subjects = @(
    "repo:${Repo}:environment:${EnvironmentName}",
    "repo:${Repo}:pull_request",
    "repo:${Owner}@${OwnerId}/${Name}@${RepoId}:environment:${EnvironmentName}",
    "repo:${Owner}@${OwnerId}/${Name}@${RepoId}:pull_request"
)
$i = 0
foreach ($subject in $subjects) {
    $i++
    Write-Host "    $subject"
    Invoke-Tool az @('identity', 'federated-credential', 'create',
        '--resource-group', $ResourceGroup,
        '--identity-name', $IdentityName,
        '--name', "github-$i",
        '--issuer', $Issuer,
        '--subject', $subject,
        '--audiences', $Audience,
        '-o', 'none') | Out-Null
}

Write-Step 'Proměnné v GitHubu (nejsou tajné – žádná hesla)'
$variables = [ordered]@{
    AZURE_CLIENT_ID       = $ClientId
    AZURE_TENANT_ID       = $TenantId
    AZURE_SUBSCRIPTION_ID = $SubscriptionId
    AZURE_RESOURCE_GROUP  = $ResourceGroup
}
foreach ($entry in $variables.GetEnumerator()) {
    Invoke-Tool gh @('variable', 'set', $entry.Key, '--body', $entry.Value, '--repo', $Repo) | Out-Null
    Write-Host "    $($entry.Key)"
}

Write-Step "GitHub prostředí $EnvironmentName"
if ($null -eq (Invoke-Tool gh @('api', '--method', 'PUT', "repos/$Repo/environments/$EnvironmentName", '--silent') -Quiet)) {
    Write-Warning "Prostředí $EnvironmentName se teď nepodařilo založit – GitHub ho vytvoří sám při prvním běhu CD."
}

if ($NoPush) {
    Write-Host ''
    Write-Host 'Hotovo. Pushněte kód do větve main (nebo spusťte workflow CD ručně).' -ForegroundColor Green
    return
}

Write-Step 'Push kódu do GitHubu (spustí workflow CD)'
$RepoRoot  = Split-Path -Parent $PSScriptRoot
$RemoteUrl = "https://github.com/$Repo.git"
Push-Location $RepoRoot
try {
    if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
        Write-Host "    zakládám lokální git repozitář v $RepoRoot"
        Invoke-Tool git @('init', '-b', 'main') | Out-Null
    }

    $hasCommit = $null -ne (Invoke-Tool git @('rev-parse', '--verify', '--quiet', 'HEAD') -Quiet)
    if (-not $hasCommit) {
        # -Quiet skryje upozornění o koncích řádků (LF/CRLF), která jsou v pořádku
        if ($null -eq (Invoke-Tool git @('add', '--all') -Quiet)) { throw 'Příkaz git add selhal.' }
        Invoke-Tool git @('commit', '-m', 'Initial commit') | Out-Null
        Write-Host '    vytvořen první commit'
    } elseif (Invoke-Tool git @('status', '--porcelain')) {
        Write-Warning 'Máte necommitnuté změny – pushnu jen to, co už je v commitech.'
    }

    $origin = Invoke-Tool git @('remote', 'get-url', 'origin') -Quiet
    $branch = Invoke-Tool git @('branch', '--show-current')
    if ($branch -ne 'main') {
        if ($null -eq $origin) {
            Invoke-Tool git @('branch', '-M', 'main') | Out-Null
            Write-Host "    větev '$branch' přejmenována na main"
        } else {
            throw "Jste ve větvi '$branch'. Workflow CD se spouští z větve main: git switch main a spusťte skript znovu."
        }
    }

    if ($null -eq $origin) {
        Invoke-Tool git @('remote', 'add', 'origin', $RemoteUrl) | Out-Null
        Write-Host "    remote origin: $RemoteUrl"
    } elseif ($origin -notmatch ('[:/]' + [regex]::Escape($Repo) + '(\.git)?/?$')) {
        throw "Remote origin ukazuje na $origin, ne na $Repo. Opravte: git remote set-url origin $RemoteUrl"
    }

    # Git použije stejný účet jako gh (ne třeba jiný účet uložený ve Windows).
    Invoke-Tool gh @('auth', 'setup-git') | Out-Null

    # Když je kód na GitHubu už aktuální, push nic nespustí – workflow CD pak spustíme ručně.
    $localSha  = Invoke-Tool git @('rev-parse', 'HEAD')
    $remoteRef = Invoke-Tool git @('ls-remote', 'origin', 'refs/heads/main')
    if ($remoteRef -and ($remoteRef -split '\s+')[0] -eq $localSha) {
        Write-Host '    kód na GitHubu už je aktuální – spouštím workflow CD ručně'
        Invoke-Tool gh @('workflow', 'run', 'cd.yml', '--ref', 'main', '--repo', $Repo) | Out-Null
    } else {
        Invoke-Interactive git @('push', '-u', 'origin', 'main') -Hint '(Pokud GitHub push odmítl jako "rejected", repozitář už obsahuje jiné commity – použijte prázdný repozitář.)'
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Hotovo. Workflow CD právě běží:' -ForegroundColor Green
Write-Host "    https://github.com/$Repo/actions" -ForegroundColor Green
Write-Host '    sledování v terminálu: gh run watch'
Write-Host '    Kdyby první běh spadl na přihlášení do Azure, oprávnění se ještě propisují –'
Write-Host '    za pár minut dejte v GitHubu "Re-run failed jobs".'
