# factory script – creates N mining repos
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

function New-Miner ($name) {
    gh repo create $name --public --clone --source . | Out-Null
    mkdir "$name\.github\workflows" -Force | Out-Null
    $url = "https://raw.githubusercontent.com/$GhUser/spin-repo/main/.github/workflows/rdp-miner.yml"
    Invoke-WebRequest $url -OutFile "$name\.github\workflows\rdp-miner.yml"
    pushd $name
    git -c user.email="bot@example.com" -c user.name="FarmBot" add . && git commit -m "deploy" && git push
    gh secret set TAILSCALE_AUTH_KEY -b"$TsKey" --repo "$GhUser/$name"
    popd
    Start-Process "https://github.com/$GhUser/$name/actions"
    Write-Host "✅  $name" -ForegroundColor Green
}

function Remove-Miner ($name) {
    gh repo delete "$GhUser/$name" --confirm | Out-Null
    Write-Host "🗑️  $name" -ForegroundColor Yellow
}

if (!$Token -or !$TsKey -or !$GhUser) {
    Write-Host "USAGE:  .\spin-farm.ps1 -Count 20 -Token ghp_XXX -TsKey tskey_XXX -GhUser YOUR_NAME" -ForegroundColor Red
    exit 1
}

if ($Delete) {
    Write-Host "Deleting farm ..." -ForegroundColor Magenta
    1..$Count | % { Remove-Miner ("miner-$_") }
    exit
}

Write-Host "Creating $Count miners ..." -ForegroundColor Cyan
1..$Count | % {
    $repo = "miner-$_"
    New-Miner $repo
}

Write-Host @"
🎉  All done!
Each repo opens in your browser – wait ~2 min for green Actions.
To destroy later:  re-run with  -Delete  switch
"@ -ForegroundColor White
