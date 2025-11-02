#requires -Version 5.1
param(
    [int]$Count = 10,
    [string]$Token = "",
    [string]$TsKey = "",
    [string]$GhUser = "",
    [switch]$Delete
)
$ErrorActionPreference = "Stop"

# install gh if missing
if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Installing GitHub CLI ..." -ForegroundColor Cyan
    iwr -useb https://raw.githubusercontent.com/cli/cli/main/install.ps1 | iex
}
if (!(gh auth status)) { gh auth login --hostname github.com }

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

if (!$Token -or !$TsKey -or !$GhUser) {
    Write-Host "ERROR:  -Token ghp_XXX  -TsKey tskey_XXX  -GhUser YOUR_NAME" -ForegroundColor Red
    exit 1
}

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
