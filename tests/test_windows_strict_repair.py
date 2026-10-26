from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "windows_strict_repair.ps1"


def test_windows_collector_defaults_to_bounded_read_only_sampling():
    source = SCRIPT.read_text(encoding="utf-8")

    assert "[ValidateRange(30, 60)]" in source
    assert "mode = 'read-only'" in source
    assert "pwsh -NoProfile" in source
    assert "Get-CounterValue" in source
    assert "status = 'unavailable'" in source


def test_windows_collector_has_no_destructive_or_broad_tuning_commands():
    source = SCRIPT.read_text(encoding="utf-8").lower()
    forbidden = (
        "remove-item",
        "restart-computer",
        "stop-process",
        "stop-service",
        "set-service",
        "new-itemproperty",
        "set-itemproperty",
        "netsh ",
        "sfc ",
        "dism ",
        "chkdsk ",
        "powercfg ",
    )

    assert all(command not in source for command in forbidden)


def test_windows_collector_records_process_identity_and_memory_semantics():
    source = SCRIPT.read_text(encoding="utf-8")

    for field in ("executablePath", "startTime", "privateBytes", "workingSetBytes", "cpuSeconds"):
        assert field in source
    assert "Working sets overlap" in source
    assert "not classified as a leak" in source


def test_windows_documentation_preflights_the_script_path():
    documentation = (
        Path(__file__).parents[1] / "docs" / "industrial-environment.md"
    ).read_text(encoding="utf-8")

    assert "C:\\Windows\\System32" in documentation
    assert "Resolve-Path -LiteralPath" in documentation
    assert "Test-Path -LiteralPath $Collector -PathType Leaf" in documentation
    assert '& "$PSHOME\\pwsh.exe" -NoProfile -File $Collector' in documentation
