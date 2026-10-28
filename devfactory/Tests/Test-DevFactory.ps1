$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '../Scripts/Repair-DevFactory.ps1'
$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
. $scriptPath
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

# A failing native command must never be reported as success.
$nativeFailed = $false
try { Invoke-FactoryNative $env:ComSpec @('/d','/c','exit 7') } catch { $nativeFailed = $_ -match 'exited with 7' }
Assert $nativeFailed 'Native failure was swallowed'
$nativeOutput = Invoke-FactoryNative $env:ComSpec @('/d','/c','echo success')
Assert ($nativeOutput -eq 'success') 'Native success output was lost'

# Mock service transitions. No real service mutations occur.
$script:serviceStatus = 'Stopped'; $script:startType = 'Disabled'; $script:writes = 0
function Get-Service { param($Name) [pscustomobject]@{ Status=$script:serviceStatus; StartType=$script:startType } }
function Set-Service { param($Name,$StartupType) $script:startType=$StartupType; $script:writes++ }
function Start-Service { param($Name) $script:serviceStatus='Running'; $script:writes++ }
function Stop-Service { param($Name) $script:serviceStatus='Stopped'; $script:writes++ }
$repair = Repair-FactoryWlan
Assert ($repair.Status -eq 'PASS' -and $repair.Original.StartType -eq 'Disabled') 'Repair/original state failed'
Assert ($script:startType -eq 'Manual' -and $script:serviceStatus -eq 'Running') 'Service transition failed'
$previousWrites = $script:writes
$null = Repair-FactoryWlan
Assert ($script:writes -eq $previousWrites) 'Already running service was modified'

$script:serviceStatus='Stopped'; $script:startType='Disabled'
function Start-Service { param($Name) throw 'simulated start failure' }
$repairFailed=$false
try { Repair-FactoryWlan } catch { $repairFailed=$_ -match 'simulated start failure' }
Assert $repairFailed 'Service failure was swallowed'
Assert ($script:startType -eq 'Disabled' -and $script:serviceStatus -eq 'Stopped') 'Rollback failed'

# Default diagnostic must never call the repair path.
function Repair-FactoryWlan { throw 'UNEXPECTED REPAIR' }
function Get-NetAdapter { param([switch]$Physical) [pscustomobject]@{ NdisPhysicalMedium=9; Name='test'; Status='Up' } }
function Get-CimInstance { param($ClassName,$Filter) }
function Invoke-FactoryNative { param($Command,$Arguments) 'mock diagnostic output' }
$diagnosis = Invoke-FactoryDiagnostic
Assert ($diagnosis.Mode -eq 'DiagnosticOnly' -and $diagnosis.Errors.Count -eq 0) 'Default diagnostic failed'
Assert ($diagnosis.Status -eq 'PARTIAL') 'Diagnostic overstated hardware validation'
function Get-NetAdapter { param([switch]$Physical) }
$diagnosis = Invoke-FactoryDiagnostic
Assert ($diagnosis.Errors.Count -gt 0) 'Missing adapter not reported'
function Invoke-FactoryNative { param($Command,$Arguments) throw 'simulated netsh failure' }
$script:pnpCollected=$false
function Get-CimInstance { param($ClassName,$Filter) $script:pnpCollected=$true }
$diagnosis = Invoke-FactoryDiagnostic
Assert $script:pnpCollected 'PnP collection was skipped after netsh failure'
Assert (($diagnosis.Errors -join ' ') -match 'simulated netsh failure') 'netsh failure was lost'
'PASS: parser, native exit codes, repair, idempotence, rollback, default read-only, missing hardware'
