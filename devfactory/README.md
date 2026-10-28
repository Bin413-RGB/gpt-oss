# Windows / WSL diagnostics

This component is separate from gpt-oss inference. It replaces the unsafe historical
repair proposal in closed, unmerged PR #6; the previously mentioned c2de590 commit
could not be resolved in this repository.

Run from Windows PowerShell 5.1 or PowerShell 7:

```powershell
.\devfactory\Scripts\Repair-DevFactory.ps1
# Optional: save to a NEW file in an existing directory; existing files are preserved.
.\devfactory\Scripts\Repair-DevFactory.ps1 -ReportPath .\wifi-diagnostic.json
# Explicit repair, from an elevated session:
.\devfactory\Scripts\Repair-DevFactory.ps1 -RepairWifi
```

The default only reads tool availability, WLAN service, physical adapters,
network device errors and netsh interface/driver/network diagnostics. Reports may
contain SSIDs and hardware identifiers; review before sharing.
Missing tools are reported, never installed automatically. Tool presence is not a
version check or proof that builds work. Exit 1 means a collection/repair error
or no physical Wi-Fi adapter; PARTIAL remains until hardware is tested.

`-RepairWifi` only starts WlanSvc and changes Disabled startup to Manual when
needed. It records the original state and attempts rollback if repair fails.
For a successful repair, restore its recorded StartType with `Set-Service WlanSvc
-StartupType <original>` and, if it was stopped, `Stop-Service WlanSvc` from an
elevated session. This interrupts Wi-Fi: do it only when rollback is needed.
Disabled adapters, airplane mode, BIOS switches and driver installation require
separate diagnosis. Verify the expected SSID and a real connection on the device.

WSL: `bash devfactory/Scripts/repair-dev-factory.sh`. It refuses non-WSL hosts,
reports missing tools (exit 1), and edits no profiles or packages.
No cleanup, DISM/SFC, Store reset, configuration overwrite, automatic SDK installation
or publishing is performed by either script.

Tests: `pwsh -NoProfile -File devfactory/Tests/Test-DevFactory.ps1`.
The pull-request workflow runs this suite on Windows PowerShell 5.1 and PowerShell
7 plus Bash syntax and host-rejection checks on Linux. Tests mock services and
native failures; they never repair the CI host.
