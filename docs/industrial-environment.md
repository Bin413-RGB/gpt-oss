# Codex industrial development environment

This repository is not an Android application template by itself; it is a GPT OSS
reference implementation. For production work, use the checklist below before
building desktop or Android applications that consume the APIs/examples here.

## One-command diagnosis

```bash
python scripts/codex_industrial_env.py
```

The command is strict: a capability is reported as ready only when the relevant
executable is on `PATH`, Android SDK environment variables point to real folders,
and repository Node dependencies are installed.

## Windows performance evidence

Run the bounded collector from **PowerShell 7 without a profile** on the Windows
host. The path after `-File` is resolved from PowerShell's current directory, not
from the directory where PowerShell is installed. First change to the repository
checkout and verify the file; this avoids the common exit code 64 / "not
recognized as the name of a script file" error when the prompt is in
`C:\Windows\System32`:

```powershell
$Repo = 'D:\Codex\gpt-oss' # Replace this with the actual checkout directory.
Set-Location -LiteralPath $Repo
$Collector = (Resolve-Path -LiteralPath '.\scripts\windows_strict_repair.ps1').Path
& "$PSHOME\pwsh.exe" -NoProfile -File $Collector
```

If the checkout location is already known, an absolute path works from any
directory:

```powershell
$Collector = 'D:\Codex\gpt-oss\scripts\windows_strict_repair.ps1'
if (-not (Test-Path -LiteralPath $Collector -PathType Leaf)) {
    throw "Collector not found: $Collector. Set it to the repository's actual path."
}
& "$PSHOME\pwsh.exe" -NoProfile -File $Collector
```

Do not copy the example path unchanged if the repository is elsewhere. Do not
search the whole disk or download another copy merely to work around a path
error; locate the existing checkout first. A successful launch prints
`Read-only baseline written to:` followed by the JSON path. The collector samples
for 30 seconds by default and writes to the existing Codex diagnostics directory
on `D:` (or a temporary per-user fallback when `D:` is not present).

Despite its historical filename, this is a read-only evidence collector. It does
not clear caches, alter the registry, reset networking, stop applications or
services, change priorities, unload models, or restart the computer. Review the
report before making one targeted, reversible change. Run it once for a baseline
and again under a comparable workload; do not interpret summed working sets as
unique memory or short-lived growth as a leak. A report file proves only that
collection completed; it does not by itself prove that Windows or an application
was repaired.

## Repository-local dependency installation

```bash
python scripts/codex_industrial_env.py --install-node
```

This runs `npm ci` in the JavaScript projects that are part of this repository:

- `examples/agents-sdk-js`
- `compatibility-test`

## Required host tools for Android production

Install these on the host image before attempting Android builds:

- JDK 17 or newer (`java`, `javac`)
- Android command-line tools (`sdkmanager`, `adb`)
- Android SDK platform and build tools for the target API level
- Gradle or the Gradle wrapper used by the Android project
- `ANDROID_HOME` or `ANDROID_SDK_ROOT` exported to the SDK directory

Recommended SDK package baseline:

```bash
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
```

## Required host tools for desktop/native production

- Python 3.12 or newer
- CMake
- Make/Ninja or the platform-native build system
- Git
- Repository development tools via `pip install -e '.[dev]'`

## Release gate

Do not release an Android or desktop artifact unless all of the following pass in
the target build environment:

```bash
python scripts/codex_industrial_env.py
python -m compileall examples/gradio/gradio_chat.py examples/streamlit/streamlit_chat.py scripts/codex_industrial_env.py
python -m ruff check examples/gradio/gradio_chat.py examples/streamlit/streamlit_chat.py scripts/codex_industrial_env.py
```
