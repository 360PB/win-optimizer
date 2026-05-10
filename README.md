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

After execution, a Markdown report is generated on your desktop.

---

# Win Optimizer / Windows 自适应硬件优化专家

> 一个 [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) Skill，智能诊断硬件配置与系统健康，自动匹配并执行分级优化策略。

## 功能特性

- **硬件画像**：CPU / 内存 / 磁盘类型（SSD/NVMe/HDD）/ 显卡（准确显存）/ 显示器（EDID）/ 分辨率
- **健康评分**：0-100 分，基于 8 个维度自动评级
- **五级策略**：低配 `lowend` / 主流 `mainstream` / 高性能 `highperf` / 游戏 `gaming` / 工作站 `workstation`
- **十二阶段执行**：诊断 → 流氓软件清理 → 启动项 → 服务 → 计划任务 → 电源 → 内存 → 磁盘 → 网络 → 隐私 → 视觉效果 → 深度清理
- **安全机制**：自动备份注册表/服务/计划任务 + 创建系统还原点
- **权限自适应**：非管理员可运行（跳过高权限操作），管理员可执行完整优化

## 快速开始

### 安装为 Kimi Skill

```bash
# 克隆到 Kimi skills 目录
git clone https://github.com/360PB/win-optimizer.git ~/.kimi/skills/windows-hardware-optimizer
```

### 直接运行

```powershell
# 仅诊断（不执行任何修改）
.\scripts\Optimize-Windows.ps1 -WhatIf

# 全自动优化（推荐以管理员身份运行）
.\scripts\Optimize-Windows.ps1 -Level auto -DeepClean

# 游戏模式
.\scripts\Optimize-Windows.ps1 -Level gaming -DeepClean

# 自动模式（无交互确认，适合批处理）
.\scripts\Optimize-Windows.ps1 -Level auto -DeepClean -AutoConfirm
```

## 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `-Level` | string | `auto` | 优化级别：`auto`/`safe`/`aggressive`/`gaming`/`workstation` |
| `-DeepClean` | switch | `$false` | 启用深度清理（Temp/缓存/DISM组件存储） |
| `-SkipRestorePoint` | switch | `$false` | 跳过创建系统还原点 |
| `-WhatIf` | switch | `$false` | 仅诊断，不执行任何修改 |
| `-AutoConfirm` | switch | `$false` | 自动确认，跳过交互提示（适合批处理） |
| `-Whitelist` | string[] | `@()` | 额外保护的启动项/服务名（支持通配符） |

## 十二阶段优化清单

| 阶段 | 操作内容 | 需要管理员 |
|------|---------|:----------:|
| 1 | 硬件诊断、健康评分、创建还原点、导出备份 | ✅ |
| 2 | 流氓软件启动项清理（360画报等） | - |
| 3 | 高影响启动项禁用（保留白名单） | - |
| 4 | 服务优化（DiagTrack/SysMain/Xbox等） | ✅ |
| 5 | 计划任务精简（QQBrowser/WPS/SoftMgr等） | ✅ |
| 6 | 电源计划（卓越性能/高性能） | ✅ |
| 7 | 虚拟内存固定大小（减少SSD写入放大） | ✅ |
| 8 | 磁盘优化（TRIM/禁用碎片整理/存储感知） | ✅ |
| 9 | 网络优化（QoS/TCP窗口/RSS） | ✅ |
| 10 | 隐私清理（遥测/广告ID/活动历史/自动播放） | ✅ |
| 11 | 视觉效果调整（按级别） | - |
| 12 | 深度清理（Temp/缩略图/浏览器缓存/DISM） | 部分 |

## 报告示例

执行完成后，桌面自动生成 Markdown 报告：

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

## Execution Summary
### Optimized (8 items)
- [x] Disabled high-impact startup: SunloginClient
- [x] Visual effects set to: Best Appearance
- [x] Background apps globally restricted
...
```

## 安全与回滚

每次执行自动创建：
- **系统还原点**：可在「系统保护」中回滚
- **注册表备份**：`C:\Windows\Temp\WinOpt_Backup_*\*.reg`
- **服务状态备份**：`Services_Backup.csv`
- **计划任务备份**：`Tasks_Backup.csv`

一键回滚命令（管理员 PowerShell）：
```powershell
$bd = (Get-ChildItem C:\Windows\Temp\WinOpt_Backup_* | Sort-Object CreationTime -Descending | Select-Object -First 1).FullName
Import-Csv "$bd\Services_Backup.csv" | ForEach-Object { Set-Service -Name $_.Name -StartupType $_.StartType -ErrorAction SilentlyContinue }
reg import "$bd\HKLM_Run.reg"
reg import "$bd\HKCU_Run.reg"
```

## License

MIT