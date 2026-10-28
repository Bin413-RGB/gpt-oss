[CmdletBinding()]
param(
    [switch]$RepairWifi,
    [string]$ReportPath
)

# No work occurs when dot-sourced (used by the isolated tests).
function Invoke-FactoryNative {
    param([string]$Command, [string[]]$Arguments)
    $output = & $Command @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "${Command} exited with ${LASTEXITCODE}: $output" }
    $output.Trim()
}

function Repair-FactoryWlan {
    $service = Get-Service -Name WlanSvc -ErrorAction Stop
    $original = [pscustomobject]@{ Status = [string]$service.Status; StartType = [string]$service.StartType }
    $changedStart = $false
    try {
        if ($service.StartType -eq 'Disabled') {
            Set-Service -Name WlanSvc -StartupType Manual -ErrorAction Stop
            $changedStart = $true
        }
        if ($service.Status -ne 'Running') { Start-Service -Name WlanSvc -ErrorAction Stop }
        if ((Get-Service -Name WlanSvc -ErrorAction Stop).Status -ne 'Running') {
            throw 'WlanSvc did not reach Running'
        }
        [pscustomobject]@{ Status = 'PASS'; Original = $original; Current = 'Running' }
    } catch {
        $failure = $_.Exception.Message
        $rollback = 'Not needed'
        if ($changedStart) {
            try {
                if ($original.Status -ne 'Running') { Stop-Service WlanSvc -ErrorAction Stop }
                Set-Service WlanSvc -StartupType Disabled -ErrorAction Stop
                $rollback = 'Restored Disabled'
            } catch { $rollback = $_.Exception.Message }
        }
        throw "Wi-Fi repair failed: $failure; rollback: $rollback"
    }
}

function Invoke-FactoryDiagnostic {
    param([switch]$ApplyWifiRepair)
    $result = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        Mode = $(if ($ApplyWifiRepair) { 'RepairWifi' } else { 'DiagnosticOnly' })
        Status = 'PARTIAL'
        Wifi = [ordered]@{}
        Tools = [ordered]@{}
        Errors = @()
    }
    if ($env:OS -ne 'Windows_NT') { throw 'This diagnostic requires Windows.' }
    if ($ApplyWifiRepair) {
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $admin) { throw '-RepairWifi requires an elevated PowerShell session.' }
    }
    foreach ($name in 'git','node','npm','python','java','cmake','ninja','flutter','adb','wsl') {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        $result.Tools[$name] = $(if ($command) { $command.Source } else { 'MISSING' })
    }
    try {
        $svc = Get-Service WlanSvc -ErrorAction Stop
        $result.Wifi.ServiceBefore = [pscustomobject]@{ Status = [string]$svc.Status; StartType = [string]$svc.StartType }
        if ($ApplyWifiRepair) { $result.Wifi.Repair = Repair-FactoryWlan }
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
            $_.NdisPhysicalMedium -eq 9 -or $_.PhysicalMediaType -eq 'Native 802.11'
        } | Select-Object Name, InterfaceDescription, Status, InterfaceGuid)
        $result.Wifi.Adapters = $adapters
        $result.Wifi.Interfaces = Invoke-FactoryNative netsh @('wlan','show','interfaces')
        $result.Wifi.Drivers = Invoke-FactoryNative netsh @('wlan','show','drivers')
        $result.Wifi.Networks = Invoke-FactoryNative netsh @('wlan','show','networks')
        $result.Wifi.HardwareTest = 'NOT_TESTED: confirm the expected SSID and connection on the device'
        if ($adapters.Count -eq 0) { $result.Errors += 'No physical Wi-Fi adapter detected; check hardware/radio/driver.' }
    } catch { $result.Errors += $_.Exception.Message }
    try {
        $result.Wifi.DeviceErrors = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Net'" -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
            Select-Object Name, ConfigManagerErrorCode, PNPDeviceID)
    } catch { $result.Errors += $_.Exception.Message }
    # Successful command execution cannot prove SSID visibility or connectivity.
    [pscustomobject]$result
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $result = Invoke-FactoryDiagnostic -ApplyWifiRepair:$RepairWifi
    $json = $result | ConvertTo-Json -Depth 8
    if ($ReportPath) {
        # CreateNew preserves any existing report. No configuration or profile is overwritten.
        $fullPath = [IO.Path]::GetFullPath($ReportPath)
        $stream = [IO.File]::Open($fullPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($json)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
    }
    $json
    if ($result.Errors.Count -gt 0) { exit 1 }
}
