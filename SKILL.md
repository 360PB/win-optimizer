---
name: windows-hardware-optimizer
description: Windows system hardware-adaptive optimization expert. Performs intelligent diagnosis of hardware specs, software environment, and system health, then executes tiered optimization strategies. Use when user asks to optimize Windows performance, clean up system junk, fix slow boot, reduce background processes, optimize memory/disk/network, or perform any system tuning on Windows 10/11. Triggers on keywords like "optimize windows", "speed up pc", "clean system", "fix slow boot", "减少后台", "优化系统", "清理垃圾", "加速开机".
---

# Windows自适应硬件优化专家

## 核心定位

自适应硬件配置的Windows系统优化专家。执行流程：**智能诊断 → 健康评分 → 分级匹配 → 安全备份 → 分阶段执行 → 生成报告**。

## 执行流程

### Step 1: 硬件与健康诊断

运行 `scripts/Optimize-Windows.ps1` 的诊断模式：

```powershell
& "{skill_dir}/scripts/Optimize-Windows.ps1" -WhatIf
```

获取：
- **硬件画像**: CPU/内存/磁盘类型/显卡/系统版本
- **软件画像**: 启动项数量、故障服务、已安装软件、Temp垃圾、事件日志错误
- **健康评分**: 0-100分（基于启动项、服务、垃圾、流氓软件等8个维度）

### Step 2: 匹配优化级别

| 级别 | 判定条件 | 核心思路 |
|------|---------|---------|
| `lowend` | 内存≤4GB 或 HDD系统盘 或 双核CPU | 能关则关，为流畅让步 |
| `mainstream` | 内存8-16GB + SSD + 四核以上 | 平衡性能与体验 |
| `highperf` | 内存≥32GB + NVMe + 八核以上 + 独显≥4GB | 释放全部潜力 |

附加模式（可叠加）：
- `gaming`: 叠加游戏优化（禁用Xbox Game Bar、全屏优化、启用HAGS）
- `workstation`: 叠加工作站优化（LargeSystemCache、禁用内存压缩）

### Step 3: 执行优化

```powershell
# 全自动（推荐）
& "{skill_dir}/scripts/Optimize-Windows.ps1" -Level auto -DeepClean

# 仅安全优化
& "{skill_dir}/scripts/Optimize-Windows.ps1" -Level safe

# 游戏模式
& "{skill_dir}/scripts/Optimize-Windows.ps1" -Level gaming -DeepClean

# 跳过还原点（快速测试）
& "{skill_dir}/scripts/Optimize-Windows.ps1" -Level auto -SkipRestorePoint
```

## 脚本参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `-Level` | string | `auto` | `auto`/`safe`/`aggressive`/`gaming`/`workstation` |
| `-DeepClean` | switch | `$false` | 执行深度垃圾清理（Temp/缓存/DISM） |
| `-SkipRestorePoint` | switch | `$false` | 跳过创建系统还原点 |
| `-WhatIf` | switch | `$false` | 仅诊断，不执行任何修改 |
| `-FixDrivers` | switch | `$false` | 启用驱动辅助修复（重启问题设备 + PnP扫描，需管理员权限） |
| `-Whitelist` | string[] | `@()` | 额外保护的启动项/服务名（支持通配符） |

## 十三阶段优化清单

脚本内部按以下顺序执行：

0. **驱动健康检查**: 检测设备异常状态、事件日志驱动错误、驱动版本与日期（>2年标记过时）、签名验证、GPU驱动详情
1. **诊断与备份**: 硬件检测、健康评分、创建还原点、导出注册表/服务/任务备份
2. **流氓软件清理**: 禁用360画报等已知流氓启动项，检测多安全软件冲突
3. **启动项清理**: 保留白名单（杀毒/输入法/显卡/音频），禁用高影响第三方项
4. **服务优化**: 根据级别选择性禁用DiagTrack/SysMain/WSearch/Xbox服务等
5. **计划任务精简**: 禁用QQBrowser/WPS/SoftMgr/OneDrive报告等第三方唤醒任务
6. **电源与性能**: 导入卓越性能计划（Pro版）或高性能（Home版），调整处理器状态
7. **内存与虚拟内存**: 动态计算并固定页面文件大小（减少SSD写入放大）
8. **磁盘优化**: 启用TRIM、禁用SSD碎片整理、配置存储感知
9. **网络优化**: 释放QoS保留带宽、优化TCP窗口、启用RSS
10. **隐私与遥测**: 禁用广告ID、诊断数据、活动历史记录、自动播放
11. **视觉效果**: 根据级别调整（低配最佳性能/主流自定义/高性能完整）
12. **深度清理**（`-DeepClean`时）: Temp/WinTemp/缩略图/浏览器缓存/DISM组件存储
13. **驱动辅助修复**（`-FixDrivers`时，需管理员）: 通过pnputil重启异常状态设备、扫描硬件变更

## 安全规范

### 强制白名单（绝不动）
- Windows Defender核心服务
- 系统关键驱动（存储/网络/显示/USB）
- BIOS/UEFI/加密服务（BitLocker/TPM）
- Windows Update核心服务（仅调整重启行为）
- 用户通过 `-Whitelist` 指定的项目

### 备份与回滚

每次执行自动创建：
- 系统还原点
- 注册表备份: `C:\Windows\Temp\WinOpt_Backup_*\*.reg`
- 服务备份: `Services_Backup.csv`
- 计划任务备份: `Tasks_Backup.csv`

一键回滚：
```powershell
$bd = (Get-ChildItem C:\Windows\Temp\WinOpt_Backup_* | Sort-Object CreationTime -Descending | Select-Object -First 1).FullName
Import-Csv "$bd\Services_Backup.csv" | ForEach-Object { Set-Service -Name $_.Name -StartupType $_.StartType -ErrorAction SilentlyContinue }
reg import "$bd\HKLM_Run.reg"
reg import "$bd\HKCU_Run.reg"
```

## 输出报告

执行完成后自动生成Markdown报告，包含：
- 硬件画像表格
- 健康评分与问题分析
- 匹配策略说明
- 已优化/已跳过清单
- 预期收益估算
- 回滚命令

## 参考文档

- **详细优化策略表**: 参见 `references/optimization-guide.md`
- **原理与数据来源**: 参见 `references/optimization-guide.md#关键优化原理`
