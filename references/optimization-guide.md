# Windows硬件优化策略参考

## 目录

1. [五级优化策略详解](#五级优化策略详解)
2. [服务禁用矩阵](#服务禁用矩阵)
3. [虚拟内存推荐配置](#虚拟内存推荐配置)
4. [游戏模式深度配置](#游戏模式深度配置)
5. [工作站模式深度配置](#工作站模式深度配置)
6. [关键优化原理](#关键优化原理)
7. [故障排查](#故障排查)

---

## 五级优化策略详解

### lowend（低配级）

适用条件：内存≤4GB 或 HDD系统盘 或 双核CPU

| 优化项 | 策略 | 原因 |
|--------|------|------|
| 视觉效果 | 最佳性能 | 减少GPU/CPU负担 |
| SysMain | 禁用 | SSD上无意义，低配更吃资源 |
| Windows Search | 禁用 | 减少后台磁盘IO |
| 虚拟内存 | 固定为物理内存2-3倍 | 避免动态分配开销 |
| 启动项 | 禁用所有非必要 | 仅保留杀毒、输入法、显卡面板 |
| 后台应用 | 全部禁用 | 减少内存占用 |
| 透明效果/动画 | 全部关闭 | 节省渲染资源 |
| 存储感知 | 启用，自动清理 | 防止C盘爆满 |
| HAGS | 禁用 | 核显/低端独显开HAGS反而增加开销 |

### mainstream（主流级）

适用条件：内存8-16GB + SSD + 四核以上

| 优化项 | 策略 | 原因 |
|--------|------|------|
| 视觉效果 | 平衡模式 | 保留平滑字体、阴影，关闭动画 |
| SysMain | 保留但限制缓存 | 加速常用应用启动 |
| Windows Search | 保留 | 快速文件搜索有价值 |
| 虚拟内存 | 系统管理或1.5倍物理内存 | 平衡写入与灵活性 |
| 启动项 | 禁用高影响项 | 保留安全软件 |
| 电源计划 | 平衡或高性能 | 按需切换 |
| TRIM | 启用 | SSD寿命与性能关键 |
| 磁盘碎片整理 | 禁用计划任务 | SSD不需要碎片整理 |

### highperf（高性能级）

适用条件：内存≥32GB + NVMe + 八核以上 + 独显≥4GB

| 优化项 | 策略 | 原因 |
|--------|------|------|
| 视觉效果 | 保留完整 | GPU完全承担得起 |
| HAGS | 启用 | 硬件加速GPU调度，降低延迟 |
| 全屏优化 | 禁用 | 减少游戏输入延迟 |
| 进程优先级 | 前台应用优先 | 确保关键任务响应 |
| 虚拟内存 | 固定8-16GB | 避免动态分配SSD写入开销 |
| LargeSystemCache | 启用(工作站模式) | 提升文件服务器性能 |
| 网络QoS | 保留带宽给关键应用 | 下载时不影响游戏/会议 |

### gaming（游戏模式）- 可叠加

| 优化项 | 策略 | 原因 |
|--------|------|------|
| Xbox Game Bar | 禁用 | 减少后台录制开销 |
| 后台录制 | 禁用 | 避免抢占GPU资源 |
| 推送通知 | 关闭 | 防止游戏中弹窗干扰 |
| 游戏模式 | 启用 | Windows原生游戏优化 |
| HPET | 谨慎禁用 | 部分平台降低延迟，部分平台反而变差 |
| 卓越性能电源 | 启用 | 解锁CPU频率响应(仅Pro/Workstation) |
| 全屏优化 | 注册表禁用 | DisableFullscreenOptimizations=1 |
| 显卡面板 | 设为性能优先 | 确保GPU全力输出 |

### workstation（工作站模式）- 可叠加

| 优化项 | 策略 | 原因 |
|--------|------|------|
| LargeSystemCache | 启用 | 提升大文件处理性能 |
| NTFS缓存 | NtfsMemoryUsage=2 | 最大化文件系统缓存 |
| 内存压缩 | 禁用(≥64GB时) | 内存≥64GB时追求低延迟 |
| 自动维护 | 禁用计划 | 避免工作时段后台干扰 |
| 网络 | 调整为吞吐量优先 | 大文件传输场景 |
| 虚拟内存 | 固定1024-2048MB | 大内存场景减少SSD写入 |

---

## 服务禁用矩阵

| 服务名 | 显示名称 | lowend | mainstream | highperf | gaming | 说明 |
|--------|----------|:------:|:----------:|:--------:|:------:|------|
| DiagTrack | 连接用户体验和遥测 | ❌ | ❌ | ❌ | ❌ | 数据收集，可安全禁用 |
| dmwappushservice | WAP推送消息路由 | ❌ | ❌ | ❌ | ❌ | 推送服务，无影响 |
| SysMain | SysMain（原Superfetch） | ❌ | ✅ | ✅ | ✅ | 低配禁用，SSD保留 |
| WSearch | Windows Search | ❌ | ✅ | ✅ | ✅ | 低配禁用，主流保留 |
| PcaSvc | 程序兼容性助手 | ❌ | ❌ | ❌ | ❌ | 兼容性弹窗，可禁用 |
| TabletInputService | 平板电脑输入服务 | ❌ | ❌ | ❌ | ❌ | 非触屏设备禁用 |
| Fax | 传真服务 | ❌ | ❌ | ❌ | ❌ | 几乎无人使用 |
| WMPNetworkSvc | WMP网络共享 | ❌ | ❌ | ❌ | ❌ | 媒体共享服务 |
| MapsBroker | 下载的地图管理器 | ❌ | ❌ | ❌ | ❌ | 不使用地图时禁用 |
| XblAuthManager | Xbox Live认证 | ❌ | ❌ | ❌ | ❌ | 不玩游戏时禁用 |
| XblGameSave | Xbox Live游戏保存 | ❌ | ❌ | ❌ | ❌ | 不玩游戏时禁用 |
| XboxNetApiSvc | Xbox网络服务 | ❌ | ❌ | ❌ | ❌ | 不玩游戏时禁用 |
| XboxGipSvc | Xbox配件管理服务 | ❌ | ❌ | ❌ | ❌ | 不玩游戏时禁用 |

---

## 虚拟内存推荐配置

| 物理内存 | 推荐虚拟内存 | 策略 |
|----------|-------------|------|
| ≤4GB | 固定8192MB | 必须足够大，防止OOM |
| 8GB | 固定4096-8192MB | 平衡选择 |
| 16GB | 固定2048-4096MB | SSD用户建议固定 |
| 32GB | 固定2048-4096MB | 减少SSD写入 |
| ≥64GB（工作站） | 固定1024-2048MB 或 禁用 | 追求极致低延迟 |

**为什么固定虚拟内存？**
- SSD用户：固定页面文件避免动态分配导致的写入放大
- 大内存用户：可大幅减小页面文件，减少SSD磨损
- 稳定性：避免系统在内存紧张时频繁调整页面文件大小导致的卡顿

---

## 游戏模式深度配置

### 注册表路径总览

```
HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR
  - AppCaptureEnabled = 0
  - GameDVR_Enabled = 0

HKCU\System\GameConfigStore
  - GameDVR_FSEBehaviorMode = 2
  - GameDVR_HonorUserFSEBehaviorMode = 1

HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers
  - HwSchMode = 2  (HAGS, Win10 2004+/Win11)

HKCU\Software\Microsoft\GameBar
  - AllowAutoGameMode = 1
```

### HPET 说明

`bcdedit /set useplatformclock false` 使用TSC替代HPET，**部分Intel平台**可降低1-3ms输入延迟；**部分AMD平台**反而导致时钟漂移。脚本默认不修改HPET，如需手动测试：

```cmd
# 禁用HPET
bcdedit /set useplatformclock false
bcdedit /set disabledynamictick yes

# 恢复HPET
bcdedit /set useplatformclock true
bcdedit /set disabledynamictick no
```

---

## 工作站模式深度配置

### LargeSystemCache

位置：`HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\LargeSystemCache`

- 值=0：默认，平衡模式
- 值=1：工作站模式，最大化文件系统缓存

影响：提升大文件（视频/数据库/VM镜像）顺序读写性能，但会减少可用物理内存。

### NTFS内存使用

位置：`HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\NtfsMemoryUsage`

- 值=0：默认
- 值=1：增加
- 值=2：最大化

### 内存压缩

位置：`HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\DisableCompression`

- 值=0：启用压缩（默认，推荐≤32GB）
- 值=1：禁用压缩（推荐≥64GB工作站）

---

## 关键优化原理

| 优化项 | 原理 | 数据来源 |
|--------|------|----------|
| 虚拟内存固定大小 | SSD用户固定页面文件避免动态分配写入放大；大内存用户可减小页面文件 | Windows官方文档、SSD厂商指南 |
| SysMain/Superfetch | HDD时代产物，SSD随机读取足够快，Superfetch反而增加写入和内存占用；但大内存+机械盘仍有价值 | Microsoft技术博客 |
| 卓越性能电源计划 | GUID e9a42b02-d5df-448d-aa00-03f14749eb61 解锁CPU频率响应延迟，仅Pro/Workstation可用 | Microsoft Docs |
| TRIM与碎片整理 | SSD必须启用TRIM且禁用碎片整理；HDD则相反 | SSD厂商白皮书 |
| 禁用全屏优化 | Windows 10/11的全屏优化会增加输入延迟和帧数波动，游戏场景建议禁用 | 游戏开发者技术论坛 |
| HPET | TSC替代HPET，部分平台降低延迟；部分AMD平台反而变差，需谨慎 | 硬件评测社区 |
| HAGS | 硬件加速GPU调度将部分调度工作从CPU卸载到GPU，降低延迟 | DirectX开发者博客 |
| QoS带宽保留 | Windows默认保留20%带宽给QoS，设为0可释放全部带宽 | Microsoft Technet |
| LargeSystemCache | 增加文件系统缓存，提升大文件吞吐量 | Windows Internals |

---

## 故障排查

### 优化后系统异常

1. **无法开机/蓝屏**
   - 进入安全模式
   - 运行备份目录中的回滚脚本
   - 或使用系统还原点恢复

2. **某些软件无法启动**
   - 检查该软件的依赖服务是否被禁用
   - 从 `Services_Backup.csv` 恢复对应服务

3. **搜索功能失效**
   - 如果禁用了WSearch，重新启用：`Set-Service WSearch -StartupType Automatic; Start-Service WSearch`

4. **游戏性能未提升**
   - 确认显卡驱动已更新
   - 检查游戏是否使用独显（双显卡设备）
   - 确认HAGS是否真正生效（需Win10 2004+且显卡驱动支持）

5. **虚拟内存警告**
   - 固定页面文件后，Windows可能弹出警告，属正常现象
   - 如提示内存不足，增大固定值
