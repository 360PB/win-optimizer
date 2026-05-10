# Win Optimizer

> [简体中文](README.md) | **English**

> Windows adaptive hardware optimization expert - A [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) Skill.

Auto-detects your hardware specs, scores system health, and executes tiered optimization strategies safely.

## Features

- **Hardware Detection**: CPU / Memory / Disk (SSD/NVMe/HDD) / GPU (accurate VRAM) / Monitor (EDID) / Resolution
- **Health Score**: 0-100 rating based on 8 dimensions
- **Tiered Optimization**: `lowend` | `mainstream` | `highperf` | `gaming` | `workstation`
- **12-Phase Execution**: From diagnosis to deep cleanup
- **Safety First**: Auto backup registry/services/tasks + system restore point
- **Admin Adaptive**: Runs without admin (skips high-privilege ops), or full power with admin

## Quick Start

### Install as Kimi Skill

```bash
git clone https://github.com/360PB/win-optimizer.git ~/.kimi/skills/windows-hardware-optimizer
```

### Run Directly

```powershell
# Diagnosis only
.\scripts\Optimize-Windows.ps1 -WhatIf

# Full optimization (admin recommended)
.\scripts\Optimize-Windows.ps1 -Level auto -DeepClean

# Gaming mode
.\scripts\Optimize-Windows.ps1 -Level gaming -DeepClean

# Auto-run without prompts (for batch files)
.\scripts\Optimize-Windows.ps1 -Level auto -DeepClean -AutoConfirm
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Level` | string | `auto` | `auto` / `safe` / `aggressive` / `gaming` / `workstation` |
| `-DeepClean` | switch | `$false` | Enable Temp/cache/DISM cleanup |
| `-SkipRestorePoint` | switch | `$false` | Skip creating system restore point |
| `-WhatIf` | switch | `$false` | Diagnosis only, no changes |
| `-AutoConfirm` | switch | `$false` | Skip interactive prompts (for batch) |
| `-Whitelist` | string[] | `@()` | Extra protected items (wildcards supported) |

## 12-Phase Optimization

| Phase | Operation | Admin Required |
|-------|-----------|:--------------:|
| 1 | Diagnosis & Backup | ✅ |
| 2 | Rogue Software Cleanup | - |
| 3 | Startup Cleanup | - |
| 4 | Service Optimization | ✅ |
| 5 | Scheduled Task Optimization | ✅ |
| 6 | Power & Performance | ✅ |
| 7 | Memory & Virtual Memory | ✅ |
| 8 | Disk Optimization | ✅ |
| 9 | Network Optimization | ✅ |
| 10 | Privacy & Telemetry | ✅ |
| 11 | Visual Effects & UI | - |
| 12 | Deep Cleanup | Partial |

## Report Example

After execution, a Markdown report is generated on your desktop.

## Safety & Rollback

Auto-created on every run: System Restore Point, Registry Backup, Service Backup, Task Backup.

One-click rollback (Admin PowerShell):
```powershell
$bd = (Get-ChildItem C:\Windows\Temp\WinOpt_Backup_* | Sort-Object CreationTime -Descending | Select-Object -First 1).FullName
Import-Csv "$bd\Services_Backup.csv" | ForEach-Object { Set-Service -Name $_.Name -StartupType $_.StartType -ErrorAction SilentlyContinue }
reg import "$bd\HKLM_Run.reg"
reg import "$bd\HKCU_Run.reg"
```

## License

MIT