#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipDiskCheck,
    [switch]$SkipNetworkReset,
    [switch]$SkipBloatAudit,
    [switch]$AutoRestartIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:NeedsRestart = $false

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Invoke-Safe {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    try {
        Write-Host "[RUN] $Name" -ForegroundColor Yellow
        & $Action
        Write-Host "[OK]  $Name" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "[FAIL] $Name -> $($_.Exception.Message)"
        return $false
    }
}

function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'يجب تشغيل السكربت بصلاحيات Administrator.'
    }
}

function Create-RestorePoint {
    Invoke-Safe -Name 'Create restore point' -Action {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" | Out-Null
        Checkpoint-Computer -Description "StrictRepair_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -RestorePointType 'MODIFY_SETTINGS' | Out-Null
    } | Out-Null
}

function Repair-SystemFiles {
    Invoke-Safe -Name 'DISM ScanHealth' -Action { DISM /Online /Cleanup-Image /ScanHealth | Out-Host } | Out-Null
    Invoke-Safe -Name 'DISM RestoreHealth' -Action { DISM /Online /Cleanup-Image /RestoreHealth | Out-Host } | Out-Null
    Invoke-Safe -Name 'SFC ScanNow' -Action { sfc /scannow | Out-Host } | Out-Null
}

function Clean-TempFiles {
    $paths = @("$env:TEMP\*", "$env:WINDIR\Temp\*")
    foreach ($path in $paths) {
        Invoke-Safe -Name "Clean $path" -Action {
            Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        } | Out-Null
    }

    Invoke-Safe -Name 'Component cleanup' -Action {
        DISM /Online /Cleanup-Image /StartComponentCleanup | Out-Host
    } | Out-Null
}

function Optimize-Services {
    $safeManualServices = @('DiagTrack', 'MapsBroker', 'Fax', 'RemoteRegistry')
    foreach ($svc in $safeManualServices) {
        Invoke-Safe -Name "Set service $svc to Manual" -Action {
            Set-Service -Name $svc -StartupType Manual -ErrorAction Stop
        } | Out-Null
    }
}

function Tune-Startup {
    Invoke-Safe -Name 'Backup startup registry' -Action {
        reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "$env:TEMP\run_backup.reg" /y | Out-Null
    } | Out-Null

    if (-not $SkipBloatAudit) {
        Invoke-Safe -Name 'List startup apps (manual review)' -Action {
            Get-CimInstance Win32_StartupCommand |
                Select-Object Name, Command, Location, User |
                Sort-Object Name |
                Format-Table -AutoSize
        } | Out-Null
    }

    Invoke-Safe -Name 'Enable startup delay optimization' -Action {
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Name StartupDelayInMSec -PropertyType DWord -Value 0 -Force | Out-Null
    } | Out-Null
}

function Reset-NetworkStack {
    if ($SkipNetworkReset) {
        Write-Host '[SKIP] Network reset disabled by flag.' -ForegroundColor DarkYellow
        return
    }

    if (Invoke-Safe -Name 'Flush DNS' -Action { ipconfig /flushdns | Out-Host }) { $global:NeedsRestart = $true }
    if (Invoke-Safe -Name 'Reset Winsock' -Action { netsh winsock reset | Out-Host }) { $global:NeedsRestart = $true }
    if (Invoke-Safe -Name 'Reset TCP/IP' -Action { netsh int ip reset | Out-Host }) { $global:NeedsRestart = $true }
}

function Optimize-BrowserNetworking {
    Write-Step 'Browser Network Acceleration'

    Invoke-Safe -Name 'Enable system DNS cache tuning' -Action {
        New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name MaxCacheTtl -PropertyType DWord -Value 86400 -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name MaxNegativeCacheTtl -PropertyType DWord -Value 60 -Force | Out-Null
    } | Out-Null

    Invoke-Safe -Name 'Enable TCP autotuning (normal)' -Action {
        netsh int tcp set global autotuninglevel=normal | Out-Host
        netsh int tcp set global rss=enabled | Out-Host
    } | Out-Null

    Invoke-Safe -Name 'Set browser-priority multimedia profile' -Action {
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'GPU Priority' -PropertyType DWord -Value 8 -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Priority' -PropertyType DWord -Value 6 -Force | Out-Null
    } | Out-Null
}

function Optimize-Edge {
    Write-Step 'Microsoft Edge Professional Tuning'
    $edgePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

    Invoke-Safe -Name 'Apply Edge performance policies' -Action {
        New-Item -Path $edgePolicy -Force | Out-Null
        New-ItemProperty -Path $edgePolicy -Name StartupBoostEnabled -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $edgePolicy -Name SleepingTabsEnabled -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $edgePolicy -Name EfficiencyModeEnabled -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $edgePolicy -Name BackgroundModeEnabled -PropertyType DWord -Value 0 -Force | Out-Null
    } | Out-Null

    Invoke-Safe -Name 'Clear Edge cache (all users)' -Action {
        Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $cachePath = Join-Path $_.FullName 'AppData\Local\Microsoft\Edge\User Data\Default\Cache\*'
            Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    } | Out-Null
}

function Optimize-Chrome {
    Write-Step 'Google Chrome Professional Tuning'
    $chromePolicy = 'HKLM:\SOFTWARE\Policies\Google\Chrome'

    Invoke-Safe -Name 'Apply Chrome performance policies' -Action {
        New-Item -Path $chromePolicy -Force | Out-Null
        New-ItemProperty -Path $chromePolicy -Name 'BackgroundModeEnabled' -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $chromePolicy -Name 'HardwareAccelerationModeEnabled' -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $chromePolicy -Name 'DnsPrefetchingEnabled' -PropertyType DWord -Value 1 -Force | Out-Null
    } | Out-Null

    Invoke-Safe -Name 'Clear Chrome cache (all users)' -Action {
        Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $cachePath = Join-Path $_.FullName 'AppData\Local\Google\Chrome\User Data\Default\Cache\*'
            Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    } | Out-Null
}

function Optimize-Firefox {
    Write-Step 'Mozilla Firefox Professional Tuning'

    Invoke-Safe -Name 'Tune Firefox user.js for each profile' -Action {
        Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $profilesRoot = Join-Path $_.FullName 'AppData\Roaming\Mozilla\Firefox\Profiles'
            if (Test-Path $profilesRoot) {
                Get-ChildItem $profilesRoot -Directory | ForEach-Object {
                    $userJs = Join-Path $_.FullName 'user.js'
                    @(
                        'user_pref("network.http.pipelining", true);',
                        'user_pref("network.http.proxy.pipelining", true);',
                        'user_pref("network.http.pipelining.maxrequests", 8);',
                        'user_pref("browser.cache.disk.enable", true);',
                        'user_pref("layers.acceleration.force-enabled", true);'
                    ) | Set-Content -Path $userJs -Encoding ASCII
                }
            }
        }
    } | Out-Null
}

function Schedule-DiskCheck {
    if ($SkipDiskCheck) {
        Write-Host '[SKIP] Disk check disabled by flag.' -ForegroundColor DarkYellow
        return
    }

    if (Invoke-Safe -Name 'Schedule CHKDSK on system drive' -Action {
        cmd /c "echo Y|chkdsk $env:SystemDrive /F /R" | Out-Host
    }) { $global:NeedsRestart = $true }
}

function Set-PerformancePlan {
    Invoke-Safe -Name 'Enable high performance plan' -Action {
        $plans = powercfg /list
        $line = $plans | Where-Object { $_ -match 'High performance' } | Select-Object -First 1
        if (-not $line) { throw 'لم يتم العثور على خطة High performance.' }
        if ($line -match '([A-Fa-f0-9\-]{36})') {
            powercfg /setactive $Matches[1] | Out-Host
        }
        else { throw 'تعذر قراءة معرف خطة الطاقة.' }
    } | Out-Null
}

Write-Step 'Windows Strict Repair + Browser Turbo Mode'
Ensure-Admin
Create-RestorePoint
Repair-SystemFiles
Clean-TempFiles
Optimize-Services
Tune-Startup
Reset-NetworkStack
Optimize-BrowserNetworking
Optimize-Edge
Optimize-Chrome
Optimize-Firefox
Schedule-DiskCheck
Set-PerformancePlan

Write-Host "`nاكتمل الإصلاح الثقيل والتحسين الاحترافي للمتصفحات." -ForegroundColor Green

if ($global:NeedsRestart -or $AutoRestartIfNeeded) {
    Write-Host 'تم رصد تغييرات تتطلب إعادة تشغيل. سيتم إعادة التشغيل خلال 20 ثانية...' -ForegroundColor Magenta
    Start-Sleep -Seconds 20
    Restart-Computer -Force
}
