# Compact Root Repair + Dev Factory for Windows
# Run from an elevated PowerShell session on Windows. This script performs one-pass checks and conditional repairs only.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Root = 'D:\Codex'
$Dirs = @('D:\Codex\Projects','D:\Codex\ReadyApps','D:\Codex\Scripts','D:\Codex\Reports','D:\DevTools','D:\Android\Sdk')
$Report = 'D:\Codex\Reports\DevFactory-Final.md'
$UbuntuScript = 'D:\Codex\Scripts\repair-dev-factory.sh'
$FlutterPath = 'D:\DevTools\Flutter'
$AndroidSdk = 'D:\Android\Sdk'
$State = [ordered]@{
  Windows = 'غير مفحوص'
  WSL = 'غير مفحوص'
  Ready = New-Object System.Collections.Generic.List[string]
  Missing = New-Object System.Collections.Generic.List[string]
  Fixed = New-Object System.Collections.Generic.List[string]
  Remaining = New-Object System.Collections.Generic.List[string]
  Exe = 'غير جاهز: لم يتم طلب/بناء تطبيق'
  Apk = 'غير جاهز: لم يتم طلب/بناء تطبيق'
}

function Add-Unique([System.Collections.Generic.List[string]]$List, [string]$Value) { if ($Value -and -not $List.Contains($Value)) { [void]$List.Add($Value) } }
function Test-Cmd([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Get-VersionLine([string]$Name, [scriptblock]$Command) {
  try { $v = & $Command 2>&1 | Select-Object -First 1; if ($LASTEXITCODE -eq 0 -or $v) { Add-Unique $State.Ready "${Name}:$v"; return $true } } catch {}
  Add-Unique $State.Missing $Name; return $false
}
function Add-UserPathIfMissing([string]$PathToAdd) {
  $current = [Environment]::GetEnvironmentVariable('Path','User')
  $parts = @($current -split ';' | Where-Object { $_ })
  if ($parts -notcontains $PathToAdd) { [Environment]::SetEnvironmentVariable('Path', (($parts + $PathToAdd) -join ';'), 'User'); Add-Unique $State.Fixed "PATH+$PathToAdd" }
}
function Set-UserEnvIfMissing([string]$Name, [string]$Value) {
  if (-not [Environment]::GetEnvironmentVariable($Name,'User')) { [Environment]::SetEnvironmentVariable($Name,$Value,'User'); Add-Unique $State.Fixed "$Name=$Value" }
}
function Install-WingetPackageIfMissing([string]$Command, [string]$PackageId, [string]$Name, [string[]]$ExtraArgs = @()) {
  if (Test-Cmd $Command) { return }
  if (-not (Test-Cmd winget)) { Add-Unique $State.Remaining "$Name: winget غير متوفر"; return }
  winget install --id $PackageId --source winget --accept-package-agreements --accept-source-agreements @ExtraArgs
  if (Test-Cmd $Command) { Add-Unique $State.Fixed "تم تثبيت $Name" } else { Add-Unique $State.Remaining "$Name لم يثبت بنجاح" }
}

foreach ($d in $Dirs) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Add-Unique $State.Remaining 'PowerShell ليس Administrator؛ تم تجاوز إصلاحات النظام والتثبيت' }

try {
  $os = Get-CimInstance Win32_OperatingSystem
  $ram = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
  $c = Get-PSDrive C -ErrorAction SilentlyContinue
  $d = Get-PSDrive D -ErrorAction SilentlyContinue
  $State.Windows = "Windows $($os.Caption) build $($os.BuildNumber)، RAM ${ram}GB، C free $([math]::Round($c.Free/1GB,1))GB، D free $([math]::Round($d.Free/1GB,1))GB"
} catch { $State.Windows = "تعذر جمع معلومات Windows: $($_.Exception.Message)" }

if (Test-Path $PROFILE) {
  try { $parseErrors = $null; $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $PROFILE -Raw), [ref]$parseErrors); if ($parseErrors) { Add-Unique $State.Remaining "PowerShell profile syntax: $($parseErrors[0].Message)" } else { Add-Unique $State.Ready 'PowerShell profile syntax' } }
  catch { Add-Unique $State.Remaining "PowerShell profile syntax: $($_.Exception.Message)" }
}

$tools = @(
  @('codex',{ codex --version }), @('git',{ git --version }), @('node',{ node --version }), @('npm',{ npm --version }),
  @('python',{ python --version }), @('java',{ java -version }), @('cmake',{ cmake --version }), @('ninja',{ ninja --version }),
  @('flutter',{ flutter --version }), @('adb',{ adb version }), @('wsl',{ wsl --status })
)
foreach ($t in $tools) { [void](Get-VersionLine $t[0] $t[1]) }

$since = (Get-Date).AddDays(-7)
foreach ($log in 'Application','System') { try { Get-WinEvent -FilterHashtable @{LogName=$log; Level=2; StartTime=$since} -MaxEvents 20 | Out-String | Out-File "D:\Codex\Reports\${log}-errors.txt" -Encoding UTF8 } catch {} }
foreach ($svc in 'wuauserv','BITS','InstallService') { try { Add-Unique $State.Ready "$svc=$((Get-Service $svc).Status)" } catch { Add-Unique $State.Remaining "$svc غير متاح" } }

$storeOrCodexAppxError = $false
try { $storeOrCodexAppxError = [bool](Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2; StartTime=$since} -MaxEvents 20 | Where-Object { $_.Message -match 'AppX|Microsoft Store|WindowsStore|Codex' }) } catch {}

if ($admin) {
  $scan = DISM /Online /Cleanup-Image /ScanHealth 2>&1 | Out-String
  $scan | Out-File 'D:\Codex\Reports\DISM-ScanHealth.txt' -Encoding UTF8
  $corrupt = $scan -match 'component store is repairable|corruption|repairable|تلف'
  if ($corrupt) {
    $restore = DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String
    $restore | Out-File 'D:\Codex\Reports\DISM-RestoreHealth.txt' -Encoding UTF8
    Add-Unique $State.Fixed 'DISM RestoreHealth'
    $sfc = sfc /scannow 2>&1 | Out-String
    $sfc | Out-File 'D:\Codex\Reports\SFC.txt' -Encoding UTF8
    Add-Unique $State.Fixed 'SFC scannow'
  }
  if ($storeOrCodexAppxError) { Get-AppxPackage Microsoft.WindowsStore | Reset-AppxPackage -ErrorAction SilentlyContinue; Add-Unique $State.Fixed 'Microsoft Store reset بسبب خطأ AppX' }
  foreach ($p in @($env:TEMP, 'C:\Windows\Temp', 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue')) { if (Test-Path $p) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } }
  Add-Unique $State.Fixed 'تنظيف TEMP/WER فقط'

  Install-WingetPackageIfMissing git Git.Git Git
  Install-WingetPackageIfMissing node OpenJS.NodeJS.LTS 'Node.js LTS'
  Install-WingetPackageIfMissing python Python.Python.3.12 Python
  Install-WingetPackageIfMissing java EclipseAdoptium.Temurin.21.JDK 'OpenJDK 21'
  Install-WingetPackageIfMissing cmake Kitware.CMake CMake
  Install-WingetPackageIfMissing ninja Ninja-build.Ninja Ninja
  if (-not (Test-Cmd cl)) { winget install --id Microsoft.VisualStudio.2022.BuildTools --source winget --override '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows11SDK.22621' --accept-package-agreements --accept-source-agreements; Add-Unique $State.Fixed 'Visual Studio Build Tools C++/SDK requested' }
  if (-not (Test-Path "$FlutterPath\bin\flutter.bat")) { git clone --depth 1 -b stable https://github.com/flutter/flutter.git $FlutterPath; Add-Unique $State.Fixed 'Flutter stable cloned' }
  if (-not (Test-Path "$AndroidSdk\cmdline-tools\latest\bin\sdkmanager.bat")) { Add-Unique $State.Remaining 'Android command line tools: حمّلها من Google أو ثبّتها يدويًا في D:\Android\Sdk\cmdline-tools\latest' }
  if (Test-Path "$AndroidSdk\cmdline-tools\latest\bin\sdkmanager.bat") { & "$AndroidSdk\cmdline-tools\latest\bin\sdkmanager.bat" 'platform-tools' 'build-tools;35.0.0' 'platforms;android-35' }
  if (-not (Test-Cmd rustc)) { if (Test-Cmd winget) { winget install --id Rustlang.Rustup --source winget --accept-package-agreements --accept-source-agreements; Add-Unique $State.Fixed 'Rust stable requested' } }
}

Add-UserPathIfMissing 'D:\DevTools\Flutter\bin'
Add-UserPathIfMissing 'D:\Android\Sdk\platform-tools'
Add-UserPathIfMissing 'D:\Android\Sdk\cmdline-tools\latest\bin'
Set-UserEnvIfMissing 'ANDROID_HOME' $AndroidSdk
Set-UserEnvIfMissing 'ANDROID_SDK_ROOT' $AndroidSdk
if (Test-Cmd node) { corepack enable; corepack prepare pnpm@latest --activate; Add-Unique $State.Fixed 'Corepack/pnpm enabled' }

@'
#!/usr/bin/env bash
set -u
ROOT_WIN='/mnt/d/Codex'
REPORT_DIR="$ROOT_WIN/Reports"
mkdir -p "$ROOT_WIN/Projects" "$ROOT_WIN/ReadyApps" "$ROOT_WIN/Scripts" "$REPORT_DIR"
READY=(); MISSING=(); FIXED=(); REMAINING=()
add_unique(){ local arr="$1" val="$2"; eval "[[ \" \${${arr}[*]} \" == *\" $val \"* ]] || ${arr}+=(\"$val\")"; }
if ! grep -qi microsoft /proc/version 2>/dev/null; then add_unique REMAINING 'ليست جلسة WSL'; fi
if ! command -v lsb_release >/dev/null 2>&1 && ! [[ -f /etc/os-release ]]; then add_unique REMAINING 'تعذر تحديد Ubuntu'; fi
sudo apt-get update
sudo dpkg --audit | tee "$REPORT_DIR/wsl-dpkg-audit.txt"
sudo apt-get check | tee "$REPORT_DIR/wsl-apt-check.txt"
need=(git curl ca-certificates build-essential cmake ninja-build python3 python3-venv python3-pip sqlite3 openjdk-21-jdk jq ripgrep fd-find)
install=()
for p in "${need[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || install+=("$p"); done
if ((${#install[@]})); then sudo apt-get install -y --no-install-recommends "${install[@]}" && FIXED+=("apt:${install[*]}"); fi
if ! command -v node >/dev/null 2>&1; then sudo apt-get install -y --no-install-recommends nodejs npm && FIXED+=('nodejs/npm'); fi
if command -v corepack >/dev/null 2>&1; then corepack enable && corepack prepare pnpm@latest --activate && FIXED+=('corepack/pnpm'); else REMAINING+=('corepack غير متوفر'); fi
ZRC="$HOME/.zshrc"; touch "$ZRC"
block='# >>> CODEX FACTORY START >>>
projects(){ cd /mnt/d/Codex/Projects; }
readyapps(){ cd /mnt/d/Codex/ReadyApps; }
factory-doctor(){ for c in git node npm pnpm python3 java cmake ninja jq rg fdfind; do command -v "$c" >/dev/null 2>&1 && { printf "%s: " "$c"; "$c" --version 2>&1 | head -1; }; done; }
# <<< CODEX FACTORY END <<<'
if ! grep -q 'CODEX FACTORY START' "$ZRC"; then printf '\n%s\n' "$block" >> "$ZRC"; FIXED+=('.zshrc aliases'); fi
printf 'WSL جاهز: %s\nإصلاحات: %s\nمتبقي: %s\n' "$(. /etc/os-release 2>/dev/null; echo ${PRETTY_NAME:-unknown})" "${FIXED[*]:-لا يوجد}" "${REMAINING[*]:-لا يوجد}" > "$REPORT_DIR/wsl-summary.txt"
'@ | Set-Content -Path $UbuntuScript -Encoding UTF8

@'
# قواعد Codex
- التقارير بالعربية وبحد أقصى 10 أسطر.
- لا تنشئ مشروعًا إلا عندما أطلب ذلك.
- تطبيق Windows الافتراضي: Electron + React + TypeScript.
- تطبيق Android + Windows: Flutter.
- الناتج النهائي للتطبيقات لاحقًا: D:\Codex\ReadyApps\APP_NAME
- لا تعتبر التطبيق جاهزًا إلا بعد وجود EXE أو APK فعلي.
- لا تسلّم ZIP أو source code فقط.
- افحص ثم عدّل أقل عدد ممكن من الملفات.
- لا تستخدم بيانات وهمية إلا بوضع Simulator واضح.
'@ | Set-Content -Path 'D:\Codex\AGENTS.md' -Encoding UTF8

if (Test-Cmd wsl) { try { wsl --status | Out-File 'D:\Codex\Reports\wsl-status.txt' -Encoding UTF8; $State.WSL = 'WSL متاح؛ شغّل repair-dev-factory.sh داخل Ubuntu' } catch { $State.WSL = "WSL error: $($_.Exception.Message)" } }
foreach ($check in @('git','node','npm','python','java','cmake','ninja','flutter','adb','wsl')) { if (Test-Cmd $check) { Add-Unique $State.Ready $check } else { Add-Unique $State.Missing $check } }
$readyText = if ($State.Ready.Count) { ($State.Ready -join ', ') } else { 'لا يوجد' }
$missingText = if ($State.Missing.Count) { ($State.Missing -join ', ') } else { 'لا يوجد' }
$fixedText = if ($State.Fixed.Count) { ($State.Fixed -join ', ') } else { 'لا يوجد' }
$remainingText = if ($State.Remaining.Count) { ($State.Remaining -join ', ') } else { 'لا يوجد' }
@(
"- حالة Windows: $($State.Windows)",
"- حالة WSL: $($State.WSL)",
"- الأدوات الجاهزة: $readyText",
"- الأدوات الناقصة: $missingText",
"- الأخطاء التي تم إصلاحها: $fixedText",
"- الأخطاء المتبقية: $remainingText",
"- مسار Flutter: $FlutterPath",
"- مسار Android SDK: $AndroidSdk",
"- حالة بناء EXE: $($State.Exe)",
"- حالة بناء APK: $($State.Apk)"
) | Set-Content -Path $Report -Encoding UTF8
Get-Content $Report
