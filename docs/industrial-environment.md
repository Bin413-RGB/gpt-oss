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
