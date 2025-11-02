#requires -Version 5.1
param(
    [int]$Count = 10,
    [string]$Token = "",
    [string]$TsKey = "",
    [string]$GhUser = "",
    [switch]$Delete
)

$ErrorActionPreference = "Stop"

if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Please install GitHub CLI first: winget install GitHub.CLI" -ForegroundColor Red
    exit 1
}

if (!(gh auth status 2>$null)) {
    Write-Host "Logging in to GitHub CLI..." -ForegroundColor Yellow
    gh auth login --hostname github.com
}

function New-Miner {
    param([string]$Name)
    Write-Host "  📦 Creating $Name..." -ForegroundColor Gray
    
    gh repo create $Name --public --clone 2>$null
    if (!$?) { Write-Host "  ❌ Failed to create $Name" -ForegroundColor Red; return }
    
    New-Item -Path "$Name\.github\workflows" -ItemType Directory -Force | Out-Null
    $yamlUrl = "https://raw.githubusercontent.com/$GhUser/spin-repo/main/.github/workflows/rdp-miner.yml"
    Invoke-WebRequest $yamlUrl -OutFile "$Name\.github\workflows\rdp-miner.yml"
    
    Push-Location $Name
    git config user.email "bot@example.com"
    git config user.name "FarmBot"
    git add .
    git commit -m "deploy"
    git push
    gh secret set TAILSCALE_AUTH_KEY -b"$TsKey" --repo "$GhUser/$Name"
    Pop-Location
    
    Start-Process "https://github.com/$GhUser/$Name/actions"
    Write-Host "  ✅ $Name ready" -ForegroundColor Green
}

function Remove-Miner {
    param([string]$Name)
    Write-Host "  🗑️ Deleting $Name..." -ForegroundColor Yellow
    gh repo delete "$GhUser/$Name" --yes 2>$null
}

if (!$Token -or !$TsKey -or !$GhUser) {
    Write-Host "ERROR: Missing parameters!" -ForegroundColor Red
    exit 1
}

if ($Delete) {
    Write-Host "Deleting $Count repos..." -ForegroundColor Magenta
    1..$Count | ForEach-Object { Remove-Miner -Name "miner-$_" }
    exit
}

Write-Host "Creating $Count miners..." -ForegroundColor Cyan
1..$Count | ForEach-Object {
    New-Miner -Name "miner-$_"
}

Write-Host "`n🎉 All done!" -ForegroundColor White
