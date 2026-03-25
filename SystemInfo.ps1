# SystemInfo.ps1
# Скрипт собирает информацию о системе и сохраняет отчёт в папку со скриптом

# Определяем папку, в которой находится скрипт
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Имя компьютера и пользователя
$computer = $env:COMPUTERNAME
$user = $env:USERNAME
$date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Имя выходного файла (в папке скрипта)
$outFile = Join-Path $scriptPath "SystemInfo_${computer}_${user}_$date.txt"

# Функция преобразования кода типа памяти в текст
function Get-MemoryTypeString {
    param([int]$typeCode)
    switch ($typeCode) {
        0  { "Unknown" }
        1  { "Other" }
        2  { "DRAM" }
        3  { "EDRAM" }
        4  { "VRAM" }
        5  { "SRAM" }
        6  { "RAM" }
        7  { "ROM" }
        8  { "FLASH" }
        9  { "EEPROM" }
        10 { "FEPROM" }
        11 { "EPROM" }
        12 { "CDRAM" }
        13 { "3DRAM" }
        14 { "SDRAM" }
        15 { "SGRAM" }
        16 { "RDRAM" }
        17 { "DDR" }
        18 { "DDR2" }
        19 { "DDR2 FB-DIMM" }
        20 { "Reserved" }
        21 { "DDR3" }
        22 { "FBD2" }
        23 { "DDR4" }
        24 { "LPDDR" }
        25 { "LPDDR2" }
        26 { "LPDDR3" }
        27 { "LPDDR4" }
        28 { "Logical non-volatile device" }
        29 { "HBM" }
        30 { "HBM2" }
        31 { "DDR5" }
        32 { "LPDDR5" }
        default { "Unknown ($typeCode)" }
    }
}

# Функция получения IP-адресов (IPv4, кроме локальных)
function Get-IPAddresses {
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Select-Object -ExpandProperty IPAddress
        if ($ips) {
            return $ips -join ", "
        } else {
            return "Не найдено"
        }
    } catch {
        return "Ошибка получения IP-адресов"
    }
}

# Функция получения списка установленных программ (исключая стандартные Windows)
function Get-InstalledPrograms {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    $programs = Get-ItemProperty $paths -ErrorAction SilentlyContinue | 
                Where-Object { $_.DisplayName -and $_.DisplayName -notmatch '^KB\d+' } |  # Исключаем обновления KB
                Select-Object DisplayName, Publisher, InstallLocation
    
    # Фильтрация: исключаем программы, установленные в системные папки Windows
    $filtered = $programs | Where-Object {
        $location = $_.InstallLocation
        # Если путь не указан, считаем, что это не стандартная программа (оставляем)
        if (-not $location) { return $true }
        
        $locLower = $location.ToLower()
        $sysRoot = $env:SystemRoot.ToLower()
        $progFiles = $env:ProgramFiles.ToLower()
        $progFilesX86 = ${env:ProgramFiles(x86)}.ToLower()
        
        # Проверяем, находится ли путь в системных папках
        $inSystem = ($locLower -like "$sysRoot\*") -or 
                    ($locLower -like "$progFiles\windowsapps\*") -or 
                    ($progFilesX86 -and ($locLower -like "$progFilesX86\windowsapps\*"))
        
        # Оставляем программы, которые НЕ в системных папках
        -not $inSystem
    }
    
    $filtered = $filtered | Sort-Object DisplayName
    
    if ($filtered) {
        $lines = @()
        foreach ($prog in $filtered) {
            $lines += "  $($prog.DisplayName) | $($prog.Publisher) | $($prog.InstallLocation)"
        }
        return $lines -join "`n"
    } else {
        return "  (нет установленных программ после фильтрации)"
    }
}

# Процессор
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuText = "Процессор: $($cpu.Name) | Ядер: $($cpu.NumberOfCores) | Логических процессоров: $($cpu.NumberOfLogicalProcessors)"

# Общий объём ОЗУ
$ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$ramGB = [math]::Round($ramBytes / 1GB, 2)

# Детальная информация по планкам памяти
$memoryModules = Get-CimInstance Win32_PhysicalMemory
$memoryDetails = @()
foreach ($mod in $memoryModules) {
    $capacityGB = [math]::Round($mod.Capacity / 1GB, 2)
    $speed = $mod.Speed
    $typeCode = $mod.SMBIOSMemoryType
    $typeStr = Get-MemoryTypeString -typeCode $typeCode
    $memoryDetails += "  Планка: $capacityGB ГБ, $typeStr, $speed МГц"
}
if ($memoryDetails.Count -eq 0) {
    $memoryDetails = "  (подробная информация о планках недоступна)"
}

# Логические диски (C:, D: и т.д.)
$logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$logicalDiskLines = @()
foreach ($disk in $logicalDisks) {
    $size = [math]::Round($disk.Size / 1GB, 2)
    $free = [math]::Round($disk.FreeSpace / 1GB, 2)
    $percent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
    $logicalDiskLines += "  $($disk.DeviceID) : $size ГБ всего, $free ГБ свободно ($percent%)"
}

# Физические диски (модели)
$physicalDisks = Get-CimInstance Win32_DiskDrive
$physicalDiskLines = @()
foreach ($pdisk in $physicalDisks) {
    $sizeGB = [math]::Round($pdisk.Size / 1GB, 2)
    $physicalDiskLines += "  $($pdisk.Model) : $sizeGB ГБ, интерфейс: $($pdisk.InterfaceType)"
}

# Операционная система
$os = Get-CimInstance Win32_OperatingSystem
$osText = "ОС: $($os.Caption) $($os.Version)"

# IP-адреса
$ipAddresses = Get-IPAddresses

# Установленные программы
$installedPrograms = Get-InstalledPrograms

# Формирование отчёта
$report = @"
Отчёт о системе
Дата: $(Get-Date)
Компьютер: $computer
Пользователь: $user
$osText

$cpuText

Оперативная память:
  Всего: $ramGB ГБ (определено системой)
  Детально по планкам:
$($memoryDetails -join "`n")

Логические диски:
$($logicalDiskLines -join "`n")

Физические диски:
$($physicalDiskLines -join "`n")

IP-адреса:
  $ipAddresses

Установленные программы (исключая стандартные Windows):
$installedPrograms
"@

# Сохранение файла
$report | Out-File -FilePath $outFile -Encoding UTF8

Write-Host "Отчёт сохранён: $outFile"
Read-Host "Нажмите Enter для выхода"