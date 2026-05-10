[CmdletBinding()]
param(
    [ValidateSet("auto","safe","aggressive","gaming","workstation")]
    [string]$Level = "auto",
    [switch]$DeepClean,
    [switch]$SkipRestorePoint,
    [switch]$WhatIf,
    [switch]$AutoConfirm,
    [string[]]$Whitelist = @()
)

$ErrorActionPreference = "Stop"
$host.ui.RawUI.WindowTitle = "Windows Hardware Optimizer v2.0"
$script:StartTime = Get-Date
$script:BackupDir = $null
$script:Results = @{
    Optimized = @()
    Skipped = @()
    Errors = @()
    Warnings = @()
}
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Write-Title($text) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
function Write-Info($text) { Write-Host "[OK] $text" -ForegroundColor Green; $script:Results.Optimized += $text }
function Write-Warn($text) { Write-Host "[!] $text" -ForegroundColor Yellow; $script:Results.Warnings += $text }
function Write-Err($text) { Write-Host "[X] $text" -ForegroundColor Red; $script:Results.Errors += $text }
function Write-Diag($text) { Write-Host "[DIAG] $text" -ForegroundColor DarkCyan }

function Get-HardwareProfile {
    $p = @{ CPU = @{}; Memory = @{}; Disk = @{}; GPU = @{}; OS = @{}; Power = @{}; Monitors = @(); DisplayResolution = $null }

    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $p.CPU.Name = $cpu.Name.Trim()
    $p.CPU.Cores = $cpu.NumberOfCores
    $p.CPU.LogicalProcessors = $cpu.NumberOfLogicalProcessors

    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $p.Memory.TotalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $p.Memory.AvailableGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)

    try {
        $memArr = Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1
        $p.Memory.Type = switch ($memArr.SMBIOSMemoryType) { 24 {"DDR3"} 26 {"DDR4"} 34 {"DDR5"} default {"Unknown"} }
        $p.Memory.SpeedMHz = $memArr.Speed
    } catch { $p.Memory.Type = "Unknown"; $p.Memory.SpeedMHz = 0 }

    $sysDrive = $env:SystemDrive.Substring(0, 1)
    $disk = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "$sysDrive`:" }
    $sysPartition = Get-CimInstance Win32_LogicalDiskToPartition | Where-Object { $_.Dependent.DeviceID -eq "$sysDrive`:" } | Select-Object -First 1
    $diskIndex = 0
    if ($sysPartition) {
        $partPath = $sysPartition.Antecedent.DeviceID
        $physDisk = Get-CimInstance Win32_DiskDriveToDiskPartition | Where-Object { $_.Dependent.DeviceID -eq $partPath } | Select-Object -First 1
        if ($physDisk) {
            $diskIndex = [regex]::Match($physDisk.Antecedent.DeviceID, '(\d+)$').Groups[1].Value
        }
    }
    $diskDrive = Get-CimInstance Win32_DiskDrive | Where-Object { $_.Index -eq $diskIndex }
    $p.Disk.Model = $diskDrive.Model
    $p.Disk.SizeGB = if ($diskDrive.Size) { [math]::Round($diskDrive.Size / 1GB, 0) } else { [math]::Round($disk.Size / 1GB, 0) }
    $p.Disk.FreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    $p.Disk.IsSSD = ($diskDrive.Model -match "SSD|NVMe|Solid State|Micron|Samsung.*SSD|WD.*Blue|Intel.*SSD|SK hynix|KINGSTON|SanDisk|Predator")
    $p.Disk.IsNVMe = ($diskDrive.Model -match "NVMe")

    # GPU detection: nvidia-smi > dxdiag > WMI
    $nvidiaSmi = $null
    try { $nvidiaSmi = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>$null } catch {}
    if ($nvidiaSmi) {
        $parts = $nvidiaSmi.Split(',')
        $p.GPU.Name = $parts[0].Trim()
        $vramMiB = [regex]::Match($parts[1], '(\d+)').Groups[1].Value
        $p.GPU.VRAMGB = [math]::Round([int]$vramMiB / 1024, 1)
    } else {
        $dxDiagFile = "$env:TEMP\dxdiag_output.txt"
        Start-Process -FilePath "dxdiag" -ArgumentList "/t", $dxDiagFile -Wait -PassThru -WindowStyle Hidden | Out-Null
        if (Test-Path $dxDiagFile) {
            $dxContent = Get-Content -Path $dxDiagFile -Raw
            $displayName = [regex]::Match($dxContent, 'Card name:\s*(.+?)\r?\n').Groups[1].Value.Trim()
            $displayMemory = [regex]::Match($dxContent, 'Dedicated Memory:\s*(\d+)\s*MB').Groups[1].Value
            if ($displayName) { $p.GPU.Name = $displayName }
            if ($displayMemory) { $p.GPU.VRAMGB = [math]::Round([int]$displayMemory / 1024, 1) }
            Remove-Item -Path $dxDiagFile -Force -ErrorAction SilentlyContinue
        }
        if ($p.GPU.Name -eq $null) {
            $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Basic Display|Microsoft Remote|OrayIddDriver|RDP|Mirror" } | Select-Object -First 1
            if ($gpu) {
                $p.GPU.Name = $gpu.Name.Trim()
                $rawVRAM = $gpu.AdapterRAM
                if ($rawVRAM -and $rawVRAM -gt 0) {
                    if ($rawVRAM -ge 4293918720) { $p.GPU.VRAMGB = -1 } else { $p.GPU.VRAMGB = [math]::Round($rawVRAM / 1GB, 1) }
                }
            }
        }
    }
    if (-not $p.GPU.Name) { $p.GPU.Name = "Unknown"; $p.GPU.VRAMGB = 0 }

    $p.OS.Caption = $os.Caption
    $p.OS.Build = [System.Environment]::OSVersion.Version.Build
    $p.OS.Edition = if ($os.Caption -match "Home") { "Home" } elseif ($os.Caption -match "Pro") { "Pro" } elseif ($os.Caption -match "Enterprise") { "Enterprise" } else { "Other" }
    $p.OS.IsWin11 = ($p.OS.Build -ge 22000)

    $activeScheme = powercfg /getactivescheme
    $p.Power.ActivePlan = if ($activeScheme -match "\((.*?)\)") { $matches[1] } else { "Unknown" }
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    $p.Power.HasBattery = ($null -ne $battery)

    # Monitor detection via WMI EDID
    try {
        $monitors = Get-CimInstance WmiMonitorID -Namespace root\wmi -ErrorAction SilentlyContinue
        $monitorsBasic = Get-CimInstance WmiMonitorBasicDisplayParams -Namespace root\wmi -ErrorAction SilentlyContinue
        foreach ($mon in $monitors) {
            if (-not $mon.Active) { continue }
            $manufacturer = [System.Text.Encoding]::ASCII.GetString($mon.ManufacturerName -ne 0)
            $model = [System.Text.Encoding]::ASCII.GetString($mon.UserFriendlyName -ne 0)
            $serial = [System.Text.Encoding]::ASCII.GetString($mon.SerialNumberID -ne 0)
            $productCode = [System.Text.Encoding]::ASCII.GetString($mon.ProductCodeID -ne 0)
            if (-not $model) { $model = $productCode }
            $basic = $monitorsBasic | Where-Object { $_.InstanceName -eq $mon.InstanceName } | Select-Object -First 1
            $sizeInch = $null
            $videoInput = "Unknown"
            if ($basic) {
                $h = $basic.MaxHorizontalImageSize
                $v = $basic.MaxVerticalImageSize
                if ($h -gt 0 -and $v -gt 0) { $sizeInch = [math]::Round([math]::Sqrt($h*$h + $v*$v) / 2.54, 1) }
                $videoInput = if ($basic.VideoInputType -eq 1) { "Digital" } else { "Analog" }
            }
            $year = if ($mon.YearOfManufacture -gt 1990) { $mon.YearOfManufacture } else { $null }
            $week = if ($mon.WeekOfManufacture -gt 0) { $mon.WeekOfManufacture } else { $null }
            $p.Monitors += [PSCustomObject]@{
                Manufacturer = $manufacturer; Model = $model; Serial = $serial
                SizeInch = $sizeInch; VideoInput = $videoInput; Year = $year; Week = $week
            }
        }
    } catch {}

    try {
        $vc = Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution -gt 0 } | Select-Object -First 1
        if ($vc) { $p.DisplayResolution = "$($vc.CurrentHorizontalResolution) x $($vc.CurrentVerticalResolution) @ $($vc.CurrentRefreshRate)Hz" }
    } catch {}

    return $p
}

function Get-OptimizationLevel($profile) {
    $mem = $profile.Memory.TotalGB
    $isSSD = $profile.Disk.IsSSD
    $cores = $profile.CPU.Cores
    if ($mem -le 4 -or (-not $isSSD) -or $cores -le 2) { return "lowend" }
    elseif ($mem -ge 32 -and $isSSD -and $cores -ge 8 -and $profile.GPU.VRAMGB -ge 4) { return "highperf" }
    else { return "mainstream" }
}

function Get-SystemHealthScore($profile) {
    $score = 100
    $startupCount = (Get-CimInstance Win32_StartupCommand).Count
    if ($startupCount -gt 8) { $score -= 10 } elseif ($startupCount -gt 5) { $score -= 5 }
    $brokenSvcs = (Get-Service | Where-Object { $_.StartType -eq "Automatic" -and $_.Status -ne "Running" }).Count
    $score -= [math]::Min($brokenSvcs * 2, 10)
    $tempSize = 0
    try { $tempSize = (Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    if ($tempSize -gt 500MB) { $score -= 5 }
    $pf = Get-WmiObject Win32_PageFileUsage -ErrorAction SilentlyContinue
    if ($profile.Memory.TotalGB -ge 16 -and $pf -and $pf.AllocatedBaseSize -lt 4096) { $score -= 5 }
    $cFreePercent = ($profile.Disk.FreeGB / $profile.Disk.SizeGB) * 100
    if ($cFreePercent -lt 20) { $score -= 10 } elseif ($cFreePercent -lt 30) { $score -= 5 }
    try {
        $regCU = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
        $roguePatterns = @("360huabao","*huabao*","*qbclipboard*","*QQBrowserAutoLaunch*")
        foreach ($pat in $roguePatterns) {
            if ($regCU.PSObject.Properties.Name -like $pat) { $score -= 15; break }
        }
    } catch {}
    return [math]::Max(0, $score)
}

function New-OptimizationBackup {
    $dir = "C:\Windows\Temp\WinOpt_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $script:BackupDir = $dir
    reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "$dir\HKLM_Run.reg" /y 2>$null | Out-Null
    reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "$dir\HKCU_Run.reg" /y 2>$null | Out-Null
    reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "$dir\VisualEffects.reg" /y 2>$null | Out-Null
    Get-Service | Select-Object Name, Status, StartType | Export-Csv "$dir\Services_Backup.csv" -NoTypeInformation
    Get-ScheduledTask | Select-Object TaskName, TaskPath, State | Export-Csv "$dir\Tasks_Backup.csv" -NoTypeInformation
    return $dir
}

function Invoke-Phase1-Diagnosis($profile) {
    Write-Title "Phase 1: Diagnosis & Backup"
    if (-not $script:IsAdmin) { Write-Warn "Running without admin rights. Some operations will be skipped." }

    $vramDisplay = if ($profile.GPU.VRAMGB -eq -1) { ">4 (WMI limited)" } elseif ($profile.GPU.VRAMGB -gt 0) { "$($profile.GPU.VRAMGB)GB" } else { "Unknown" }
    Write-Diag "CPU: $($profile.CPU.Name) ($($profile.CPU.Cores)C/$($profile.CPU.LogicalProcessors)T)"
    Write-Diag "Memory: $($profile.Memory.TotalGB)GB $($profile.Memory.Type) @ $($profile.Memory.SpeedMHz)MHz"
    Write-Diag "Disk: $($profile.Disk.Model) ($($profile.Disk.SizeGB)GB, free $($profile.Disk.FreeGB)GB) [$(if($profile.Disk.IsNVMe){'NVMe'}elseif($profile.Disk.IsSSD){'SSD'}else{'HDD'})]"
    Write-Diag "GPU: $($profile.GPU.Name) ($vramDisplay)"
    if ($profile.Monitors.Count -gt 0) {
        foreach ($mon in $profile.Monitors) {
            $sizeStr = if ($mon.SizeInch) { " $($mon.SizeInch) inch" } else { "" }
            $yearStr = if ($mon.Year) { " ($($mon.Year))" } else { "" }
            Write-Diag "Monitor: $($mon.Manufacturer) $($mon.Model)$sizeStr [$($mon.VideoInput)]$yearStr"
        }
    }
    if ($profile.DisplayResolution) { Write-Diag "Resolution: $($profile.DisplayResolution)" }
    Write-Diag "OS: $($profile.OS.Caption) Build $($profile.OS.Build) [$($profile.OS.Edition)]"

    if ($script:IsAdmin -and -not $SkipRestorePoint) {
        $rpName = "WinOpt_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Checkpoint-Computer -Description $rpName -RestorePointType MODIFY_SETTINGS
        Write-Info "System restore point created: $rpName"
    } elseif (-not $script:IsAdmin) {
        Write-Warn "Admin rights required for restore point. Skipped."
    } else {
        Write-Warn "Restore point creation skipped by user."
    }

    if ($script:IsAdmin) {
        $bd = New-OptimizationBackup
        Write-Info "Backup exported to: $bd"
    } else {
        Write-Warn "Admin rights required for backup. Skipped."
    }
}

function Invoke-Phase2-RogueCleanup {
    Write-Title "Phase 2: Rogue Software Cleanup"
    $roguePatterns = @("360huabao","*huabao*","*qbclipboard*","*QQBrowserAutoLaunch*","*SoftMgr*")
    $regPaths = @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
    foreach ($rp in $regPaths) {
        $props = Get-Item -Path $rp -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
        foreach ($propName in $props) {
            foreach ($pattern in $roguePatterns) {
                if ($propName -like $pattern) {
                    Remove-ItemProperty -Path $rp -Name $propName -Force -ErrorAction SilentlyContinue
                    Write-Info "Disabled rogue startup: $propName"
                }
            }
        }
    }
    $securitySoftware = @("360*","QQPCMgr*","Tencent*Manager*","*Safe*","*Security*")
    $installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.DisplayName -and ($securitySoftware | ForEach-Object { $_.DisplayName -like $_ }) -contains $true }
    if ($installed -and $installed.Count -gt 1) {
        Write-Warn "Multiple security/management software detected: $($installed.DisplayName -join ', ') - recommend keeping only one"
    }
}

function Invoke-Phase3-StartupCleanup {
    Write-Title "Phase 3: Startup Cleanup"
    $safeWhitelist = @("SecurityHealth","ctfmon","Windows Defender*","*Audio*","*NVIDIA*","*AMD*","*Realtek*","*Intel*Graphics*","Everything","OneDrive")
    $safeWhitelist += $Whitelist
    $highImpact = @("Spotify*","Steam*","Adobe*","*AutoLaunch*","*AutoStart*","*Updater*","*Update*","Feishu*","*Sunlogin*")
    $regPaths = @{ HKCU = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; HKLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" }
    foreach ($scope in $regPaths.Keys) {
        $path = $regPaths[$scope]
        $props = Get-Item -Path $path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
        foreach ($name in $props) {
            $isWhite = $safeWhitelist | Where-Object { $name -like $_ }
            if ($isWhite) { $script:Results.Skipped += "Startup whitelist: $name"; continue }
            $isHighImpact = $highImpact | Where-Object { $name -like $_ }
            if ($isHighImpact) {
                Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction SilentlyContinue
                Write-Info "Disabled high-impact startup [$scope]: $name"
            }
        }
    }
}

function Invoke-Phase4-ServiceOptimization($level) {
    Write-Title "Phase 4: Service Optimization"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping service optimization."; return }
    $disableMap = @{
        lowend = @("DiagTrack","dmwappushservice","SysMain","WSearch","PcaSvc","TabletInputService","Fax","WMPNetworkSvc","MapsBroker","XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc")
        safe = @("DiagTrack","dmwappushservice","PcaSvc","Fax","WMPNetworkSvc","MapsBroker")
        mainstream = @("DiagTrack","dmwappushservice","PcaSvc","Fax","WMPNetworkSvc","MapsBroker")
        highperf = @("DiagTrack","dmwappushservice","PcaSvc","Fax","WMPNetworkSvc")
        gaming = @("DiagTrack","dmwappushservice","PcaSvc","Fax","WMPNetworkSvc","MapsBroker","XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc")
        workstation = @("DiagTrack","dmwappushservice","PcaSvc","Fax","WMPNetworkSvc","MapsBroker","XblAuthManager","XblGameSave","XboxNetApiSvc")
    }
    $targets = if ($disableMap.ContainsKey($level)) { $disableMap[$level] } else { $disableMap["safe"] }
    foreach ($svc in $targets) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $service) { continue }
        $isWhite = $Whitelist | Where-Object { $svc -like $_ }
        if ($isWhite) { $script:Results.Skipped += "Service whitelist: $svc"; continue }
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Info "Disabled service: $($service.DisplayName) ($svc)"
    }
}

function Invoke-Phase5-TaskOptimization {
    Write-Title "Phase 5: Scheduled Task Optimization"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping task optimization."; return }
    $patterns = @("*QQBrowser*","*SoftMgrUpdate*","*WpsUpdate*","*WpsWake*","*mihomo-party*","*OneDrive Reporting*","*OneDrive Standalone Update*","*GoogleUpdate*")
    foreach ($pat in $patterns) {
        Get-ScheduledTask -TaskName $pat -ErrorAction SilentlyContinue | ForEach-Object {
            Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false | Out-Null
            Write-Info "Disabled scheduled task: $($_.TaskName)"
        }
    }
}

function Invoke-Phase6-Power($level, $profile) {
    Write-Title "Phase 6: Power & Performance"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping power optimization."; return }
    $isPro = ($profile.OS.Edition -match "Pro|Enterprise|Workstation")
    if ($isPro -and ($level -eq "highperf" -or $level -eq "gaming" -or $level -eq "workstation")) {
        powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
        powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
        Write-Info "Ultimate Performance power plan activated"
    } else {
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null
        Write-Info "High Performance power plan activated"
    }
    $minProc = switch ($level) { "highperf" { 100 } "gaming" { 100 } "workstation" { 100 } "mainstream" { 5 } default { 0 } }
    powercfg -setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN $minProc 2>$null | Out-Null
    powercfg -setactive scheme_current 2>$null | Out-Null
    powercfg -setacvalueindex scheme_current sub_usb 2a737441-1930-4402-8d77-b2bebba308a3 0 2>$null | Out-Null
    powercfg -change -disk-timeout-ac 0 2>$null | Out-Null
    Write-Info "Power parameters optimized (CPU min: ${minProc}%)"
}

function Invoke-Phase7-PageFile($profile) {
    Write-Title "Phase 7: Memory & Virtual Memory"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping pagefile modification."; return }
    $totalRAM = $profile.Memory.TotalGB
    $pageSize = switch ($totalRAM) {
        { $_ -le 4 }  { 8192 }
        { $_ -le 8 }  { 8192 }
        { $_ -le 16 } { 4096 }
        { $_ -le 32 } { 4096 }
        default       { 2048 }
    }
    $comp = Get-WmiObject Win32_ComputerSystem
    $comp.AutomaticManagedPagefile = $false
    $comp.Put() | Out-Null
    Get-WmiObject Win32_PageFileSetting | ForEach-Object { $_.Delete() | Out-Null }
    Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name="C:\pagefile.sys"; InitialSize=$pageSize; MaximumSize=$pageSize} | Out-Null
    Write-Info "Pagefile fixed at ${pageSize}MB (C:\pagefile.sys)"
}

function Invoke-Phase8-Disk($profile) {
    Write-Title "Phase 8: Disk Optimization"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping disk TRIM/defrag config."; return }
    fsutil behavior set DisableDeleteNotify 0 | Out-Null
    Write-Info "TRIM enabled"
    Get-ScheduledTask -TaskName "*defrag*" -ErrorAction SilentlyContinue | Disable-ScheduledTask -Confirm:$false | Out-Null
    Write-Info "SSD defrag schedule disabled"
    $ssPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
    if (-not (Test-Path $ssPath)) { New-Item -Path $ssPath -Force | Out-Null }
    Set-ItemProperty -Path $ssPath -Name "01" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $ssPath -Name "2048" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $ssPath -Name "04" -Value 7 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $ssPath -Name "08" -Value 30 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Info "Storage Sense configured (Temp 7d / Recycle 30d)"
}

function Invoke-Phase9-Network {
    Write-Title "Phase 9: Network Optimization"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping network optimization."; return }
    $qosPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
    if (-not (Test-Path $qosPath)) { New-Item -Path $qosPath -Force | Out-Null }
    Set-ItemProperty -Path $qosPath -Name "NonBestEffortLimit" -Value 0 -Type DWord -Force
    Write-Info "QoS reserve bandwidth set to 0%"
    $tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
    if (-not (Test-Path $tcpParams)) { New-Item -Path $tcpParams -Force | Out-Null }
    Set-ItemProperty -Path $tcpParams -Name "TcpWindowSize" -Value 64240 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $tcpParams -Name "GlobalMaxTcpWindowSize" -Value 64240 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $tcpParams -Name "Tcp1323Opts" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Info "TCP window optimized"
    $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.HardwareInterface } | Select-Object -First 1
    if ($nic) {
        Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword "*RSS" -RegistryValue "1" -ErrorAction SilentlyContinue
        Write-Info "RSS enabled on $($nic.Name)"
    }
}

function Invoke-Phase10-Privacy {
    Write-Title "Phase 10: Privacy & Telemetry"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping privacy optimization."; return }
    $paths = @{
        AdInfo = @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Value = 0 }
        Telemetry = @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Value = 0 }
        Activity = @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; Value = 0 }
        ActivityUpload = @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "UploadUserActivities"; Value = 0 }
        AutoRun = @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "NoDriveTypeAutoRun"; Value = 255 }
    }
    foreach ($key in $paths.Keys) {
        $cfg = $paths[$key]
        if (-not (Test-Path $cfg.Path)) { New-Item -Path $cfg.Path -Force | Out-Null }
        Set-ItemProperty -Path $cfg.Path -Name $cfg.Name -Value $cfg.Value -Type DWord -Force
    }
    Write-Info "Telemetry / AdID / Activity History / AutoRun disabled"
}

function Invoke-Phase11-Visual($level) {
    Write-Title "Phase 11: Visual Effects & UI"
    $fxSetting = switch ($level) { "lowend" { 2 } "mainstream" { 3 } default { 1 } }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "VisualFXSetting" -Value $fxSetting -Force
    $labels = @{ 2 = "Best Performance"; 3 = "Custom"; 1 = "Best Appearance" }
    Write-Info "Visual effects set to: $($labels[$fxSetting])"
    $bgPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    if (-not (Test-Path $bgPath)) { New-Item -Path $bgPath -Force | Out-Null }
    Set-ItemProperty -Path $bgPath -Name "GlobalUserDisabled" -Value 1 -Type DWord -Force
    Write-Info "Background apps globally restricted"
}

function Invoke-Phase12-DeepClean {
    Write-Title "Phase 12: Deep Cleanup"
    $temp = $env:TEMP
    $before = 0
    try { $before = (Get-ChildItem -Path $temp -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    Remove-Item -Path "$temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    $after = 0
    try { $after = (Get-ChildItem -Path $temp -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
    $freed = [math]::Round(($before - $after) / 1MB, 2)
    Write-Info "User Temp freed: ${freed} MB"

    if ($script:IsAdmin) {
        $winTemp = "C:\Windows\Temp"
        $before2 = 0
        try { $before2 = (Get-ChildItem -Path $winTemp -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
        Remove-Item -Path "$winTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
        $after2 = 0
        try { $after2 = (Get-ChildItem -Path $winTemp -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch {}
        $freed2 = [math]::Round(($before2 - $after2) / 1MB, 2)
        Write-Info "Windows Temp freed: ${freed2} MB"
    } else {
        Write-Warn "Admin rights required. Skipping Windows Temp cleanup."
    }

    $thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Remove-Item -Path "$thumbPath\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
    Start-Process explorer
    Write-Info "Thumbnail cache reset"

    @("$env:LOCALAPPDATA\Microsoft\Edge","$env:LOCALAPPDATA\Google\Chrome") | ForEach-Object {
        $cache = "$_\User Data\Default\Code Cache\js"
        if (Test-Path $cache) {
            Remove-Item -Path "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Info "Browser cache cleaned"
        }
    }

    Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Recent\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Info "Recent files cleared"

    if ($script:IsAdmin) {
        Write-Host "[DIAG] Running DISM component store cleanup (may take 3-10 min)..." -ForegroundColor DarkCyan
        Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
        Write-Info "DISM component store cleanup complete"
    } else {
        Write-Warn "Admin rights required. Skipping DISM cleanup."
    }
}

function Invoke-GamingExtras($profile) {
    Write-Title "Gaming Mode Extras"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping gaming extras."; return }
    $gameBarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
    if (-not (Test-Path $gameBarPath)) { New-Item -Path $gameBarPath -Force | Out-Null }
    Set-ItemProperty -Path $gameBarPath -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $gameBarPath -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
    Write-Info "Xbox Game Bar / Background recording disabled"

    $fsPath = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $fsPath)) { New-Item -Path $fsPath -Force | Out-Null }
    Set-ItemProperty -Path $fsPath -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force
    Set-ItemProperty -Path $fsPath -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 1 -Type DWord -Force
    Write-Info "Fullscreen optimizations disabled"

    if ($profile.OS.Build -ge 19041) {
        $hagsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Set-ItemProperty -Path $hagsPath -Name "HwSchMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Info "Hardware Accelerated GPU Scheduling (HAGS) enabled"
    }

    $gmPath = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $gmPath)) { New-Item -Path $gmPath -Force | Out-Null }
    Set-ItemProperty -Path $gmPath -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
    Write-Info "Windows Game Mode enabled"
}

function Invoke-WorkstationExtras($profile) {
    Write-Title "Workstation Mode Extras"
    if (-not $script:IsAdmin) { Write-Warn "Admin rights required. Skipping workstation extras."; return }
    $memGB = $profile.Memory.TotalGB
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Info "LargeSystemCache enabled"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsMemoryUsage" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Info "NTFS memory usage maximized"
    if ($memGB -ge 64) {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisableCompression" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Info "Memory compression disabled (large memory workstation)"
    }
}

function New-OptimizationReport($profile, $level, $score) {
    $reportPath = "$env:USERPROFILE\Desktop\Windows_Optimization_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
    $elapsed = [math]::Round(((Get-Date) - $script:StartTime).TotalMinutes, 1)
    $diskType = if ($profile.Disk.IsNVMe) { "NVMe" } elseif ($profile.Disk.IsSSD) { "SSD" } else { "HDD" }
    $scoreColor = if ($score -ge 80) { "🟢" } elseif ($score -ge 60) { "🟡" } elseif ($score -ge 40) { "🟠" } else { "🔴" }
    $vramDisplay = if ($profile.GPU.VRAMGB -eq -1) { ">4 (WMI limited)" } elseif ($profile.GPU.VRAMGB -gt 0) { "$($profile.GPU.VRAMGB)GB" } else { "Unknown" }
    $monitorDisplay = if ($profile.Monitors.Count -gt 0) { "$($profile.Monitors[0].Manufacturer) $($profile.Monitors[0].Model) ($($profile.Monitors[0].SizeInch) inch)" } else { "Unknown" }
    $optimizedItems = ($script:Results.Optimized | ForEach-Object { "- [x] $_" }) -join "`n"
    $skippedItems = ($script:Results.Skipped | ForEach-Object { "- [ ] $_" }) -join "`n"
    $warningItems = ($script:Results.Warnings | ForEach-Object { "- ⚠ $_" }) -join "`n"

    $report = @"
# Windows Adaptive Optimization Report v2.0

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Duration: ${elapsed} minutes

## Hardware Profile

| Component | Spec | Level |
|-----------|------|-------|
| CPU | $($profile.CPU.Name) ($($profile.CPU.Cores)C/$($profile.CPU.LogicalProcessors)T) | $level |
| Memory | $($profile.Memory.TotalGB)GB $($profile.Memory.Type) @ $($profile.Memory.SpeedMHz)MHz | $level |
| Disk | $($profile.Disk.Model) ($($profile.Disk.SizeGB)GB, free $($profile.Disk.FreeGB)GB) [$diskType] | $level |
| GPU | $($profile.GPU.Name) ($vramDisplay) | $level |
| Monitor | $monitorDisplay | $level |
| Resolution | $(if($profile.DisplayResolution){$profile.DisplayResolution}else{'Unknown'}) | $level |
| OS | $($profile.OS.Caption) Build $($profile.OS.Build) [$($profile.OS.Edition)] | $level |

## Health Score

- **Score**: $score/100 ($scoreColor)

## Matched Strategy

Configuration classified as **$level**. Corresponding strategy applied.

## Execution Summary

### Optimized ($($script:Results.Optimized.Count) items)
$optimizedItems

### Skipped ($($script:Results.Skipped.Count) items)
$skippedItems

### Warnings ($($script:Results.Warnings.Count) items)
$warningItems

## Safety & Rollback

- Backup location: $($script:BackupDir)
- Rollback command (Admin PowerShell):
```powershell
`$bd = (Get-ChildItem C:\Windows\Temp\WinOpt_Backup_* | Sort-Object CreationTime -Descending | Select-Object -First 1).FullName
Import-Csv "`$bd\Services_Backup.csv" | ForEach-Object { Set-Service -Name `$_.Name -StartupType `$_.StartType -ErrorAction SilentlyContinue }
reg import "`$bd\HKLM_Run.reg"
reg import "`$bd\HKCU_Run.reg"
```

## Notes

1. Some optimizations require **reboot** to take full effect
2. Pagefile changes **must reboot**
3. If issues occur, use system restore point or backup files to rollback
4. Recommend re-running detection every 3 months
"@

    $report | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Info "Report saved: $reportPath"
    return $reportPath
}

function Main {
    Write-Title "Windows Hardware Optimizer v2.0"
    Write-Host "  Mode: $(if($WhatIf){'WhatIf'}else{'Execute'}) | Level: $Level | DeepClean: $DeepClean | Admin: $script:IsAdmin"
    Write-Host "========================================" -ForegroundColor Cyan

    $profile = Get-HardwareProfile
    $detectedLevel = Get-OptimizationLevel $profile
    if ($Level -eq "auto") { $Level = $detectedLevel }
    $healthScore = Get-SystemHealthScore $profile

    $vramDisplay = if ($profile.GPU.VRAMGB -eq -1) { ">4 (WMI limited)" } elseif ($profile.GPU.VRAMGB -gt 0) { "$($profile.GPU.VRAMGB)GB" } else { "Unknown" }

    Write-Host "`n========== Hardware Detection Report ==========" -ForegroundColor Cyan
    Write-Host "CPU: $($profile.CPU.Name) ($($profile.CPU.Cores)C/$($profile.CPU.LogicalProcessors)T)"
    Write-Host "Memory: $($profile.Memory.TotalGB)GB $($profile.Memory.Type) @ $($profile.Memory.SpeedMHz)MHz"
    Write-Host "Disk: $($profile.Disk.Model) ($($profile.Disk.SizeGB)GB, free $($profile.Disk.FreeGB)GB) [$(if($profile.Disk.IsNVMe){'NVMe'}elseif($profile.Disk.IsSSD){'SSD'}else{'HDD'})]"
    Write-Host "GPU: $($profile.GPU.Name) ($vramDisplay)"
    if ($profile.Monitors.Count -gt 0) {
        foreach ($mon in $profile.Monitors) {
            $sizeStr = if ($mon.SizeInch) { " $($mon.SizeInch) inch" } else { "" }
            $yearStr = if ($mon.Year) { " ($($mon.Year))" } else { "" }
            Write-Host "Monitor: $($mon.Manufacturer) $($mon.Model)$sizeStr [$($mon.VideoInput)]$yearStr"
        }
    }
    if ($profile.DisplayResolution) { Write-Host "Resolution: $($profile.DisplayResolution)" }
    Write-Host "OS: $($profile.OS.Caption) Build $($profile.OS.Build) [$($profile.OS.Edition)]"
    Write-Host "`n>>> Detected Level: $detectedLevel | Execute Level: $Level <<<" -ForegroundColor Green
    Write-Host ">>> Health Score: $healthScore/100 <<<" -ForegroundColor $(if($healthScore -ge 80){"Green"}elseif($healthScore -ge 60){"Yellow"}else{"Red"})

    if ($WhatIf) {
        Write-Host "`n[WhatIf] Diagnosis only. No changes made." -ForegroundColor Magenta
        Write-Host "To execute: .\Optimize-Windows.ps1 -Level $Level $(if($DeepClean){'-DeepClean'})"
        return
    }

    if (-not $AutoConfirm) {
        Write-Host "`nPress Enter to start optimization, or Ctrl+C to cancel..." -ForegroundColor Yellow
        Read-Host
    }

    Invoke-Phase1-Diagnosis $profile
    Invoke-Phase2-RogueCleanup
    Invoke-Phase3-StartupCleanup
    Invoke-Phase4-ServiceOptimization $Level
    Invoke-Phase5-TaskOptimization
    Invoke-Phase6-Power $Level $profile
    Invoke-Phase7-PageFile $profile
    Invoke-Phase8-Disk $profile
    Invoke-Phase9-Network
    Invoke-Phase10-Privacy
    Invoke-Phase11-Visual $Level
    if ($DeepClean) { Invoke-Phase12-DeepClean }
    if ($Level -eq "gaming") { Invoke-GamingExtras $profile }
    if ($Level -eq "workstation") { Invoke-WorkstationExtras $profile }

    $reportPath = New-OptimizationReport $profile $Level $healthScore

    Write-Title "Optimization Complete"
    Write-Host "Optimized: $($script:Results.Optimized.Count) items" -ForegroundColor Green
    Write-Host "Skipped: $($script:Results.Skipped.Count) items" -ForegroundColor Gray
    if ($script:Results.Warnings.Count -gt 0) { Write-Host "Warnings: $($script:Results.Warnings.Count) items" -ForegroundColor Yellow }
    if ($script:Results.Errors.Count -gt 0) { Write-Host "Errors: $($script:Results.Errors.Count) items" -ForegroundColor Red }
    Write-Host "`nReport: $reportPath" -ForegroundColor Cyan
    Write-Host "Backup: $($script:BackupDir)" -ForegroundColor Gray
    Write-Host "`n⚠️ Please reboot to apply all changes!" -ForegroundColor Yellow
    if (-not $AutoConfirm) {
        Read-Host "Press Enter to exit"
    }
}

Main
