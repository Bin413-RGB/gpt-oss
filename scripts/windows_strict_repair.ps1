#Requires -Version 7.0
<#
.SYNOPSIS
Collects bounded, read-only evidence for Windows, Codex, Ollama, and ChatGPT.

.DESCRIPTION
This command deliberately does not stop processes, clear caches, edit the registry,
reset networking, or restart Windows.  Its output is suitable for deciding whether
a *separate*, reviewed repair is justified.  The historical file name is retained
so existing callers fail safe instead of invoking the former broad "tuning" script.
#>
[CmdletBinding()]
param(
    [ValidateRange(30, 60)]
    [int]$SampleSeconds = 30,

    [ValidateRange(1, 5)]
    [int]$SampleIntervalSeconds = 1,

    [string]$OutputDirectory = 'D:\Codex\Diagnostics\Codex-Execution-20261002'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'This collector must run on the actual Windows host in PowerShell 7 (pwsh -NoProfile).'
}

function Get-CommandEvidence {
    param([Parameter(Mandatory)][string]$Name)

    $commands = @(Get-Command $Name -All -ErrorAction SilentlyContinue)
    [ordered]@{
        name = $Name
        paths = @($commands | ForEach-Object Source | Where-Object { $_ } | Select-Object -Unique)
        found = $commands.Count -gt 0
    }
}

function Invoke-VersionProbe {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Arguments = @('--version')
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return [ordered]@{ name = $Name; status = 'missing'; output = $null }
    }

    $output = & $command.Source @Arguments 2>&1 | Out-String
    [ordered]@{
        name = $Name
        status = if ($LASTEXITCODE -eq 0) { 'ok' } else { 'probe-failed' }
        output = $output.Trim()
    }
}

function Get-TargetProcesses {
    $pattern = '^(ChatGPT|chrome|codex|ollama)$'
    @(
        Get-CimInstance Win32_Process |
            Where-Object { $_.Name -replace '\.exe$', '' -match $pattern } |
            ForEach-Object {
                $process = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
                [ordered]@{
                    name = $_.Name
                    pid = $_.ProcessId
                    parentPid = $_.ParentProcessId
                    executablePath = $_.ExecutablePath
                    startTime = if ($process) { $process.StartTime.ToUniversalTime().ToString('o') } else { $null }
                    priority = if ($process) { $process.PriorityClass.ToString() } else { $null }
                }
            }
    )
}

function Get-CounterValue {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $sample = Get-Counter -Counter $Path -MaxSamples 1 -ErrorAction Stop
        [ordered]@{ status = 'ok'; value = [double]$sample.CounterSamples[0].CookedValue }
    }
    catch {
        # A failed counter is explicit; it is never converted to a misleading zero.
        [ordered]@{ status = 'unavailable'; error = $_.Exception.Message }
    }
}

function Get-ResourceSample {
    $os = Get-CimInstance Win32_OperatingSystem
    $page = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
    $targets = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -replace '\.exe$', '' -match '^(ChatGPT|chrome|codex|ollama)$' })

    [ordered]@{
        timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        system = [ordered]@{
            availableMemoryBytes = [int64]$os.FreePhysicalMemory * 1KB
            totalMemoryBytes = [int64]$os.TotalVisibleMemorySize * 1KB
            commitBytes = Get-CounterValue '\Memory\Committed Bytes'
            commitLimitBytes = Get-CounterValue '\Memory\Commit Limit'
            diskSecondsPerTransfer = Get-CounterValue '\PhysicalDisk(_Total)\Avg. Disk sec/Transfer'
            diskQueueLength = Get-CounterValue '\PhysicalDisk(_Total)\Current Disk Queue Length'
            pagesPerSecond = Get-CounterValue '\Memory\Pages/sec'
            pageFileUsage = @($page | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage)
        }
        processes = @($targets | ForEach-Object {
            $process = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
            [ordered]@{
                name = $_.Name
                pid = $_.ProcessId
                startTime = if ($process) { try { $process.StartTime.ToUniversalTime().ToString('o') } catch { $null } } else { $null }
                cpuSeconds = if ($process) { $process.CPU } else { $null }
                privateBytes = if ($process) { $process.PrivateMemorySize64 } else { $null }
                workingSetBytes = if ($process) { $process.WorkingSet64 } else { $null }
                readBytes = $_.ReadTransferCount
                writeBytes = $_.WriteTransferCount
            }
        })
    }
}

function Get-ExistingPathEvidence {
    param([string[]]$Paths)
    @($Paths | ForEach-Object {
        [ordered]@{ path = $_; exists = Test-Path -LiteralPath $_ }
    })
}

$started = Get-Date
$fallback = Join-Path $env:TEMP 'Codex-Diagnostics\Codex-Execution-20261002'
$outputRoot = [System.IO.Path]::GetPathRoot($OutputDirectory)
if ($outputRoot -and -not (Test-Path -LiteralPath $outputRoot -ErrorAction SilentlyContinue)) {
    $OutputDirectory = $fallback
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$initialProcesses = Get-TargetProcesses
$samples = [System.Collections.Generic.List[object]]::new()
$sampleCount = [math]::Ceiling($SampleSeconds / $SampleIntervalSeconds)
for ($index = 0; $index -lt $sampleCount; $index++) {
    $samples.Add((Get-ResourceSample))
    if ($index -lt ($sampleCount - 1)) { Start-Sleep -Seconds $SampleIntervalSeconds }
}

$ollamaState = [ordered]@{ status = 'not-installed-or-not-running'; output = $null }
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    $ollamaOutput = & (Get-Command ollama).Source ps 2>&1 | Out-String
    $ollamaState = [ordered]@{
        status = if ($LASTEXITCODE -eq 0) { 'ok' } else { 'probe-failed' }
        output = $ollamaOutput.Trim()
    }
}

$report = [ordered]@{
    schemaVersion = 1
    mode = 'read-only'
    startedUtc = $started.ToUniversalTime().ToString('o')
    completedUtc = (Get-Date).ToUniversalTime().ToString('o')
    host = [ordered]@{
        windows = Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber
        powershell = $PSVersionTable.PSVersion.ToString()
        processArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    }
    invocation = [ordered]@{
        scriptPath = $PSCommandPath
        workingDirectory = (Get-Location).Path
    }
    path = [ordered]@{
        raw = $env:PATH
        entries = @($env:PATH -split ';')
        duplicates = @($env:PATH -split ';' | Group-Object | Where-Object Count -gt 1 | Select-Object Name, Count)
        commands = @('pwsh', 'codex', 'ollama', 'ChatGPT') | ForEach-Object { Get-CommandEvidence $_ }
    }
    versions = @(
        Invoke-VersionProbe pwsh @('--version')
        Invoke-VersionProbe codex @('--version')
        Invoke-VersionProbe ollama @('--version')
    )
    inspectedPaths = Get-ExistingPathEvidence @(
        (Join-Path $HOME '.codex\cli-local.config.toml'),
        (Join-Path $HOME '.codex\config.toml'),
        (Join-Path $HOME '.codex\history.jsonl'),
        'D:\Codex\Diagnostics\Memory-20261001',
        'D:\Codex\Diagnostics\Codex-Execution-20261002'
    )
    environment = [ordered]@{
        CODEX_WINDOWS_REGISTERED_CORE = $env:CODEX_WINDOWS_REGISTERED_CORE
        OLLAMA_HOST = $env:OLLAMA_HOST
        OLLAMA_KEEP_ALIVE = $env:OLLAMA_KEEP_ALIVE
        OLLAMA_NUM_PARALLEL = $env:OLLAMA_NUM_PARALLEL
        OLLAMA_MAX_LOADED_MODELS = $env:OLLAMA_MAX_LOADED_MODELS
    }
    initialProcesses = $initialProcesses
    ollama = $ollamaState
    samples = $samples
    limitations = @(
        'No UI timing was inferred; an interactive reproduction is required for ChatGPT latency.',
        'Working sets overlap and must not be summed as unique memory.',
        'Short-term growth alone is not classified as a leak.',
        'No process, service, cache, registry key, database, conversation, or model was changed.'
    )
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $OutputDirectory "windows-codex-baseline-$stamp.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
Write-Host "Read-only baseline written to: $reportPath"
Write-Host 'No repair was applied. Review evidence before selecting one reversible change.'
