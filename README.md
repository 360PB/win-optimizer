# Win Optimizer

> Windows adaptive hardware optimization expert - A [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) Skill.

Auto-detects your hardware specs, scores system health, and executes tiered optimization strategies safely.

## Features

- **Hardware Detection**: CPU / Memory / Disk (SSD/NVMe/HDD) / GPU / Monitor / Resolution
- **Health Score**: 0-100 rating based on 8 dimensions
- **Tiered Optimization**: `lowend` | `mainstream` | `highperf` | `gaming` | `workstation`
- **12-Phase Execution**: From diagnosis to deep cleanup
- **Safety First**: Auto backup registry/services/tasks + system restore point
- **Admin Adaptive**: Runs without admin (skips high-privilege ops), or full power with admin

## Quick Start

### Install as Kimi Skill

```bash
# Clone to Kimi skills directory
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

| Parameter | Description |
|-----------|-------------|
| `-Level` | `auto` / `safe` / `aggressive` / `gaming` / `workstation` |
| `-DeepClean` | Enable Temp/cache/DISM cleanup |
| `-SkipRestorePoint` | Skip creating system restore point |
| `-WhatIf` | Diagnosis only, no changes |
| `-AutoConfirm` | Skip interactive prompts |
| `-Whitelist` | Extra protected items |

## Report Example

After execution, a Markdown report is generated on your desktop:

```markdown
# Windows Adaptive Optimization Report v2.0

## Hardware Profile
| Component | Spec |
|-----------|------|
| CPU | Intel i7-9700 (8C/8T) |
| Memory | 48GB DDR4 |
| Disk | Predator SSD GM7000 1TB [NVMe] |
| GPU | NVIDIA RTX 3060 (12GB) |
| Monitor | AOC 2490W1 (24 inch) |
| Resolution | 1920 x 1080 @ 60Hz |

## Health Score
- **Score**: 80/100 (🟢)
```

## Safety

- **Restore Point**: Created before any changes
- **Registry Backup**: `C:\Windows\Temp\WinOpt_Backup_*`
- **Service Backup**: `Services_Backup.csv`
- **One-Click Rollback**: Included in every report

## License

MIT