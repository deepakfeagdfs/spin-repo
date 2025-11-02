#requires -Version 5.1
<#
  Spin-Farm – create/delete N identical mining repos
  Usage (PowerShell):
    iwr -useb https://raw.githubusercontent.com/YOUR_USER/spin-repo/main/spin-farm.ps1 | iex; spin-farm -Count 20 -Token ghp_XXX -TsKey tskey_XXX -GhUser YOUR_NAME
#>
param(
    [int]$Count = 10,
    [string]$Token = "",
    [string]$TsKey  = "",
    [string]$GhUser = "",
    [switch]$Delete
)

$ErrorActionPreference = "Stop"

# ----------  GitHub CLI check (skip if already installed)  ----------
if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Installing GitHub CLI ..." -ForegroundColor Cyan
    # use winget (Windows 10/11) or chocolatey fallback
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id GitHub.CLI --accept-package-agreements --accept-source-agreements
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install gh -y
    } else {
        Write-Host "Please install GitHub CLI manually:  https://cli.github.com" -ForegroundColor Red
        exit 1
    }
}
if (!(gh auth status)) {
    Write-Host "Logging in to GitHub CLI ..." -ForegroundColor Yellow
    gh auth login --hostname github.com
}

# ----------  helpers  ----------
function New-Miner {
    param([string]$Name)
    Write-Host "  📦  Creating repo $Name ..." -ForegroundColor Gray
    gh repo create $Name --public --clone --source . | Out-Null

    mkdir "$Name\.github\workflows" -Force | Out-Null
    $yamlUrl = "https://raw.githubusercontent.com/$GhUser/spin-repo/main/.github/workflows/rdp-miner.yml"
    Invoke-WebRequest $yamlUrl -OutFile "$Name\.github\workflows\rdp-miner.yml"

    Push-Location $Name
    git -c user.email="bot@example.com" -c user.name="FarmBot" add .
    git commit -m "deploy miner"
    git push
    gh secret set TAILSCALE_AUTH_KEY -b"$TsKey" --repo "$GhUser/$Name"
    Pop-Location

    Start-Process "https://github.com/$GhUser/$Name/actions"   # open browser tab
    Write-Host "  ✅  $Name  ready" -ForegroundColor Green
}

function Remove-Miner {
    param([string]$Name)
    Write-Host "  🗑️  Deleting repo $Name ..." -ForegroundColor Yellow
    gh repo delete "$GhUser/$Name" --confirm | Out-Null
}

# ----------  sanity  ----------
if (!$Token -or !$TsKey -or !$GhUser) {
    Write-Host "USAGE:  -Token ghp_XXX  -TsKey tskey_XXX  -GhUser YOUR_NAME" -ForegroundColor Red
    exit 1
}

# ----------  main  ----------
if ($Delete) {
    Write-Host "Deleting farm ($Count repos) ..." -ForegroundColor Magenta
    1..$Count | ForEach-Object { Remove-Miner -Name "miner-$_" }
    exit
}

Write-Host "Creating $Count miners ..." -ForegroundColor Cyan
1..$Count | ForEach-Object {
    $repo = "miner-$_"
    New-Miner -Name $repo
}

Write-Host @"
🎉  All done!
Each repo opens in your browser – wait ~2 min for green Actions.
To destroy later:  re-run with  -Delete  switch
"@ -ForegroundColor White
