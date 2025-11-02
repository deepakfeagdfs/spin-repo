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
    Write-Host "GitHub CLI not found. Install with: winget install GitHub.CLI" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (!(gh auth status 2>$null)) {
    gh auth login --hostname github.com
}

function New-Miner {
    param([string]$Name)
    Write-Host "Creating $Name..." -ForegroundColor Cyan
    
    gh repo create $Name --public --clone 2>$null
    New-Item -Path "$Name\.github\workflows" -ItemType Directory -Force | Out-Null
    
    $yamlUrl = "https://raw.githubusercontent.com/$GhUser/spin-repo/main/.github/workflows/rdp-miner.yml"
    Invoke-WebRequest $yamlUrl -OutFile "$Name\.github\workflows\rdp-miner.yml"
    
    Set-Location $Name
    git config user.email "bot@example.com"
    git config user.name "FarmBot"
    git add .
    git commit -m "deploy"
    git push
    gh secret set TAILSCALE_AUTH_KEY -b"$TsKey" --repo "$GhUser/$Name"
    Set-Location ..
    
    Start-Process "https://github.com/$GhUser/$Name/actions"
    Write-Host "Done: $Name" -ForegroundColor Green
}

function Remove-Miner {
    param([string]$Name)
    gh repo delete "$GhUser/$Name" --yes 2>$null
}

if (!$Token -or !$TsKey -or !$GhUser) {
    Write-Host "Missing parameters" -ForegroundColor Red
    exit 1
}

if ($Delete) {
    1..$Count | ForEach-Object { Remove-Miner -Name "miner-$_" }
    exit
}

1..$Count | ForEach-Object {
    New-Miner -Name "miner-$_"
}

Write-Host "All done!" -ForegroundColor Green
