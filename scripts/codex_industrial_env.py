#!/usr/bin/env python3
"""Diagnose and prepare a production-grade Codex development workstation.

The script is intentionally strict: it never marks a capability ready unless the
required executable and, where possible, project dependency directories exist.
It can install repository-local Node dependencies, but system SDKs such as the
Android SDK must be installed by the host image/package manager first.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NODE_PROJECTS = [ROOT / "examples" / "agents-sdk-js", ROOT / "compatibility-test"]
REQUIRED_TOOLS = {
    "core": ["git", "python", "pip"],
    "python_quality": ["ruff", "pytest"],
    "javascript": ["node", "npm"],
    "native_desktop": ["cmake", "make"],
    "android": ["java", "javac", "adb", "sdkmanager", "gradle"],
}
ANDROID_ENV_VARS = ["ANDROID_HOME", "ANDROID_SDK_ROOT"]


@dataclass(frozen=True)
class CheckResult:
    name: str
    ok: bool
    detail: str
    remediation: str = ""


def run(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def version_for(executable: str) -> str:
    candidates = {
        "java": [executable, "-version"],
        "javac": [executable, "-version"],
        "cmake": [executable, "--version"],
        "make": [executable, "--version"],
        "adb": [executable, "version"],
        "sdkmanager": [executable, "--version"],
        "gradle": [executable, "--version"],
    }
    command = candidates.get(executable, [executable, "--version"])
    completed = run(command)
    output = completed.stdout.strip().splitlines()
    return output[0] if output else "available"


def check_tool(executable: str) -> CheckResult:
    path = shutil.which(executable)
    if not path:
        return CheckResult(
            executable,
            False,
            "missing",
            f"Install `{executable}` and ensure it is on PATH.",
        )
    return CheckResult(executable, True, f"{path} ({version_for(executable)})")


def check_android_env() -> list[CheckResult]:
    results: list[CheckResult] = []
    configured = [name for name in ANDROID_ENV_VARS if os.environ.get(name)]
    if configured:
        for name in configured:
            value = Path(os.environ[name]).expanduser()
            results.append(
                CheckResult(
                    name,
                    value.exists(),
                    str(value),
                    "Point this variable to an existing Android SDK directory.",
                )
            )
    else:
        results.append(
            CheckResult(
                "ANDROID_HOME/ANDROID_SDK_ROOT",
                False,
                "not configured",
                "Install Android command-line tools and export ANDROID_HOME or ANDROID_SDK_ROOT.",
            )
        )
    return results


def check_node_project(project: Path) -> CheckResult:
    node_modules = project / "node_modules"
    package_lock = project / "package-lock.json"
    if node_modules.is_dir() and package_lock.is_file():
        return CheckResult(str(project.relative_to(ROOT)), True, "node_modules present")
    return CheckResult(
        str(project.relative_to(ROOT)),
        False,
        "node_modules missing",
        f"Run `npm ci` in {project.relative_to(ROOT)}.",
    )


def install_node_projects() -> list[CheckResult]:
    results: list[CheckResult] = []
    for project in NODE_PROJECTS:
        completed = run(["npm", "ci"], cwd=project)
        results.append(
            CheckResult(
                f"npm ci:{project.relative_to(ROOT)}",
                completed.returncode == 0,
                completed.stdout.strip()[-1000:] or "completed",
                "Fix npm/network errors, then rerun this command.",
            )
        )
    return results


def diagnose() -> list[CheckResult]:
    results: list[CheckResult] = []
    for group, tools in REQUIRED_TOOLS.items():
        results.append(CheckResult(group, True, "capability group"))
        results.extend(check_tool(tool) for tool in tools)
    results.extend(check_android_env())
    results.extend(check_node_project(project) for project in NODE_PROJECTS)
    return results


def print_text(results: list[CheckResult]) -> None:
    width = max(len(result.name) for result in results)
    for result in results:
        mark = "PASS" if result.ok else "FAIL"
        print(f"{mark:4} {result.name:<{width}} {result.detail}")
        if not result.ok and result.remediation:
            print(f"     remediation: {result.remediation}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Diagnose and prepare Codex Android/desktop development readiness."
    )
    parser.add_argument("--install-node", action="store_true", help="Run npm ci in repository Node projects.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    args = parser.parse_args()

    results = install_node_projects() if args.install_node else diagnose()
    if args.json:
        print(json.dumps([result.__dict__ for result in results], indent=2, ensure_ascii=False))
    else:
        print(f"Codex industrial environment report: {platform.platform()}")
        print_text(results)

    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
