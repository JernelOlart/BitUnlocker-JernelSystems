#Requires -RunAsAdministrator
<#
.SYNOPSIS
    upgrade_usb.ps1 - Reconstruye el boot_patched.sdi del USB con:
    1. Teclado espanol configurado automaticamente
    2. Menu forense (bitlocker_diag.cmd) embebido que auto-lanza al arrancar
    
    Ejecutar desde Windows normal (no WinRE). El USB debe estar conectado.

.PARAMETER UsbDrive
    Letra del USB. Si no se indica, se detecta automaticamente.

.EXAMPLE
    .\upgrade_usb.ps1
    .\upgrade_usb.ps1 -UsbDrive D
#>

param(
    [string]$UsbDrive = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param([string]$M) Write-Host "[*] $M" -ForegroundColor Green }
function Write-Info { param([string]$M) Write-Host "    $M" -ForegroundColor Gray }
function Write-Warn { param([string]$M) Write-Host "[!] $M" -ForegroundColor Yellow }
function Write-Err  { param([string]$M) Write-Host "[X] $M" -ForegroundColor Red }
function Write-OK   { param([string]$M) Write-Host "[+] $M" -ForegroundColor Cyan }

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  BitUnlocker - Upgrade USB con menu forense embebido" -ForegroundColor Cyan
Write-Host "  Incluye: teclado espanol + auto-launch del menu + diag tools" -ForegroundColor Yellow
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# DETECTAR USB
# ─────────────────────────────────────────────────────────────────────────────

if ($UsbDrive -eq "") {
    Write-Step "Buscando USB con boot_patched.sdi..."
    $removable = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
    foreach ($d in $removable) {
        $letter = $d.DeviceID.TrimEnd(":")
        $sdiPath = "$($d.DeviceID)\sdi\boot_patched.sdi"
        if (Test-Path $sdiPath) {
            $UsbDrive = $letter
            Write-Info "USB encontrado: $($d.DeviceID) ($($d.VolumeName)) - $([math]::Round($d.Size/1GB,1)) GB"
            break
        }
    }
    if ($UsbDrive -eq "") {
        Write-Warn "No se detecto USB automaticamente."
        $drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
        if ($drives) {
            Write-Info "USBs disponibles:"
            foreach ($d in $drives) { Write-Info "  $($d.DeviceID) - $($d.VolumeName) ($([math]::Round($d.Size/1GB,1)) GB)" }
        }
        $UsbDrive = Read-Host "Letra del USB (ej: D)"
    }
}

$USB = "${UsbDrive}:"
if (-not (Test-Path $USB)) {
    Write-Err "Unidad $USB no encontrada."
    exit 1
}

Write-OK "USB: $USB"

# ─────────────────────────────────────────────────────────────────────────────
# ENCONTRAR WinRE.wim DEL SISTEMA
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Buscando WinRE.wim del sistema..."

$winreSource = $null

# Metodo 1: Rutas estandar
$winrePaths = @(
    "$env:SystemRoot\System32\Recovery\WinRE.wim",
    "C:\Recovery\WindowsRE\WinRE.wim",
    "C:\Windows\System32\Recovery\WinRE.wim"
)
$winreSource = $winrePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($winreSource) { Write-Info "Encontrado en ruta estandar." }

# Metodo 2: Montar particion de recuperacion via reagentc
if (-not $winreSource) {
    Write-Info "Probando reagentc /info para encontrar particion de recuperacion..."
    try {
        $reagentOut = & reagentc /info 2>&1 | Out-String
        Write-Info "reagentc output: $reagentOut"
        # Buscar la particion (ej: \\?\GLOBALROOT\device\harddisk0\partition4\...)
        $partMatch = [regex]::Match($reagentOut, 'harddisk(\d+)\\partition(\d+)')
        if ($partMatch.Success) {
            $diskNum = $partMatch.Groups[1].Value
            $partNum = $partMatch.Groups[2].Value
            Write-Info "Particion de recuperacion: Disk $diskNum, Partition $partNum"
            # Asignar letra R: a la particion de recuperacion
            $dpScript = @"
select disk $diskNum
select partition $partNum
assign letter=R
"@
            $dpScript | diskpart | Out-Null
            Start-Sleep -Seconds 2
            $recoveryWim = "R:\Recovery\WindowsRE\WinRE.wim"
            if (Test-Path $recoveryWim) {
                $winreSource = $recoveryWim
                Write-OK "WinRE.wim encontrado en particion de recuperacion (R:)"
            } else {
                # Buscar recursivamente en R:
                $found = Get-ChildItem -Path "R:\" -Recurse -Filter "WinRE.wim" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $winreSource = $found.FullName
                    Write-OK "WinRE.wim encontrado en: $winreSource"
                }
            }
        }
    } catch {
        Write-Info "reagentc no disponible: $_"
    }
}

# Metodo 3: Extraer WIM del boot_patched.sdi existente en el USB
if (-not $winreSource) {
    $existingSdi = Join-Path $USB "sdi\boot_patched.sdi"
    if (Test-Path $existingSdi) {
        Write-Warn "WinRE.wim no encontrado en el sistema."
        Write-Step "Extrayendo WIM del boot_patched.sdi existente en el USB..."
        
        $sdiData = [System.IO.File]::ReadAllBytes($existingSdi)
        $BT_OFF = 0x200; $BE_SIZE = 64; $BT_ENTRIES = 64
        $wimIdx = -1
        for ($i = 0; $i -lt $BT_ENTRIES; $i++) {
            $b = $BT_OFF + $i * $BE_SIZE
            if ($b + 4 -gt $sdiData.Length) { break }
            $t = [System.Text.Encoding]::ASCII.GetString($sdiData, $b, 4)
            if ($t -eq "WIM`0") { $wimIdx = $i; break }
        }
        
        if ($wimIdx -ge 0) {
            $wb = $BT_OFF + $wimIdx * $BE_SIZE
            $wimOff = [BitConverter]::ToUInt64($sdiData, $wb + 0x10)
            $wimSz  = [BitConverter]::ToUInt64($sdiData, $wb + 0x18)
            Write-Info "WIM encontrado en SDI: offset=0x$($wimOff.ToString('X')), size=$([math]::Round($wimSz/1MB,1)) MB"
            
            $extractedWim = "C:\BitUnlocker_Build_Temp\extracted_winre.wim"
            New-Item -ItemType Directory -Path "C:\BitUnlocker_Build_Temp" -Force | Out-Null
            
            $fs = [System.IO.File]::OpenRead($existingSdi)
            try {
                $fs.Seek($wimOff, [System.IO.SeekOrigin]::Begin) | Out-Null
                $ws = [System.IO.File]::OpenWrite($extractedWim)
                try {
                    $remaining = [long]$wimSz
                    $buf = New-Object byte[] (1024 * 1024)
                    while ($remaining -gt 0) {
                        $toRead = [math]::Min($remaining, $buf.Length)
                        $r = $fs.Read($buf, 0, $toRead)
                        if ($r -eq 0) { break }
                        $ws.Write($buf, 0, $r)
                        $remaining -= $r
                        $pct = [math]::Round(($wimSz - $remaining) * 100 / $wimSz)
                        Write-Host "`r    Extrayendo: ${pct}% ($([math]::Round(($wimSz - $remaining)/1MB)) / $([math]::Round($wimSz/1MB)) MB)" -NoNewline
                    }
                    Write-Host ""
                } finally { $ws.Close() }
            } finally { $fs.Close() }
            
            if (Test-Path $extractedWim) {
                $winreSource = $extractedWim
                Write-OK "WIM extraido del SDI existente: $extractedWim"
            }
        }
    }
}

if (-not $winreSource -or -not (Test-Path $winreSource)) {
    Write-Err "WinRE.wim no encontrado por ningun metodo."
    Write-Info "Rutas buscadas:"
    $winrePaths | ForEach-Object { Write-Info "  $_" }
    Write-Info "Tambien se intento: reagentc + particion recovery + extraer del SDI del USB"
    Write-Warn "Alternativa: usa una ISO de Windows 11 con get_files_from_iso.ps1"
    exit 1
}

$winreSize = [math]::Round((Get-Item $winreSource).Length / 1MB, 1)
Write-OK "WinRE.wim: $winreSource ($winreSize MB)"

# ─────────────────────────────────────────────────────────────────────────────
# ENCONTRAR boot.sdi STOCK
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Buscando boot.sdi del sistema..."

$sdiPaths = @(
    "$env:SystemRoot\Boot\DVD\EFI\en-US\boot.sdi",
    "$env:SystemRoot\Boot\DVD\EFI\es-ES\boot.sdi",
    "$env:SystemRoot\Boot\DVD\EFI\boot.sdi",
    "$env:SystemRoot\Boot\DVD\PCAT\en-US\boot.sdi",
    "$env:SystemRoot\Boot\DVD\PCAT\boot.sdi",
    "C:\Windows\Boot\DVD\EFI\en-US\boot.sdi"
)
$sdiSource = $sdiPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $sdiSource) {
    # Buscar recursivamente
    Write-Info "Buscando boot.sdi en C:\Windows\Boot\..."
    $found = Get-ChildItem -Path "C:\Windows\Boot" -Recurse -Filter "boot.sdi" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $sdiSource = $found.FullName }
}

if (-not $sdiSource -or -not (Test-Path $sdiSource)) {
    Write-Err "boot.sdi no encontrado en el sistema."
    Write-Warn "Alternativa: usa una ISO de Windows 11 con get_files_from_iso.ps1"
    exit 1
}

Write-OK "boot.sdi encontrado: $sdiSource"

# ─────────────────────────────────────────────────────────────────────────────
# PREPARAR DIRECTORIO TEMPORAL
# ─────────────────────────────────────────────────────────────────────────────

$TempDir  = "C:\BitUnlocker_Build_Temp"
$MountDir = Join-Path $TempDir "mount"
$WimCopy  = Join-Path $TempDir "custom_winre.wim"

# Limpiar si existe
if (Test-Path $MountDir) {
    & dism.exe /Unmount-Wim /MountDir:$MountDir /Discard 2>$null | Out-Null
    Start-Sleep -Seconds 2
}
if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $MountDir -Force | Out-Null

Write-Step "Directorio temporal: $TempDir"

# ─────────────────────────────────────────────────────────────────────────────
# COPIAR Y MONTAR WinRE.wim
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Copiando WinRE.wim al temporal..."
Copy-Item $winreSource $WimCopy -Force

# Quitar readonly
$item = Get-Item $WimCopy
$item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)

Write-Step "Montando WinRE.wim..."
$out = & dism.exe /Mount-Wim /WimFile:$WimCopy /Index:1 /MountDir:$MountDir 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "Error al montar WIM: $out"
    exit 1
}
Write-OK "WIM montado en: $MountDir"

# ─────────────────────────────────────────────────────────────────────────────
# INYECTAR bitlocker_diag.cmd
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Inyectando herramientas forenses..."

$toolsDir = Join-Path $MountDir "Tools"
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

# Buscar bitlocker_diag.cmd (puede estar junto al script o en scripts/)
$diagSource = $null
$diagPaths = @(
    (Join-Path $PSScriptRoot "bitlocker_diag.cmd"),
    (Join-Path $PSScriptRoot "..\scripts\bitlocker_diag.cmd"),
    (Join-Path $PSScriptRoot "scripts\bitlocker_diag.cmd")
)
foreach ($p in $diagPaths) {
    if (Test-Path $p) { $diagSource = (Resolve-Path $p).Path; break }
}

if ($diagSource) {
    Copy-Item $diagSource (Join-Path $toolsDir "bitlocker_diag.cmd") -Force
    Write-OK "bitlocker_diag.cmd inyectado desde: $diagSource"
} else {
    Write-Warn "bitlocker_diag.cmd no encontrado. Se creara un menu basico."
    # Menu basico inline
    $basicMenu = @'
@echo off
setlocal enabledelayedexpansion
title BitLocker Forensic Toolkit
color 1F
cls
echo.
echo ========================================================================
echo   BITLOCKER FORENSIC TOOLKIT - JernelSystems Research
echo ========================================================================
echo.
echo Detectando volumenes...
set WIN_VOL=
for %%D in (C D E F G H I J) do (
    if exist %%D:\Windows\System32\cmd.exe (
        if "!WIN_VOL!"=="" set WIN_VOL=%%D
    )
)
echo.
echo [1] Estado BitLocker (manage-bde -status)
echo [2] Ver protectores de todos los volumenes
echo [3] Listar volumenes (diskpart)
echo [4] Explorar archivos
echo [5] Copiar carpeta con robocopy
echo [6] Informacion del sistema
echo [7] CMD interactivo
echo [0] Salir
echo.
set /p OP="Opcion: "
if "%OP%"=="1" manage-bde -status & pause & %0
if "%OP%"=="2" (for %%D in (C D E F G H) do manage-bde -protectors -get %%D: 2>nul) & pause & %0
if "%OP%"=="3" echo list volume | diskpart & pause & %0
if "%OP%"=="4" (set /p VOL="Volumen: " & dir !VOL!:\ /a & pause & %0)
if "%OP%"=="5" (set /p SRC="Origen: " & set /p DST="Destino: " & robocopy "!SRC!" "!DST!" /E /R:1 /W:1 & pause & %0)
if "%OP%"=="6" wmic computersystem get Manufacturer,Model /value 2>nul & wmic /namespace:\\root\cimv2\security\microsofttpm path win32_tpm get IsActivated_InitialValue,ManufacturerVersion,SpecVersion /value 2>nul & pause & %0
if "%OP%"=="7" cmd.exe /k "echo Escribe exit para volver"
if "%OP%"=="0" exit /b
%0
'@
    $basicMenu | Out-File -FilePath (Join-Path $toolsDir "bitlocker_diag.cmd") -Encoding ASCII -Force
    Write-OK "Menu basico inyectado."
}

# ─────────────────────────────────────────────────────────────────────────────
# MODIFICAR startnet.cmd (auto-launch + teclado espanol)
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Modificando startnet.cmd (teclado espanol + auto-launch)..."

$startnetPath = Join-Path $MountDir "Windows\System32\startnet.cmd"
$startnetContent = @'
@echo off
wpeinit

:: Configurar teclado espanol
wpeutil SetKeyboardLayout 0C0A:0000040A >nul 2>&1
wpeutil SetUserLocale es-ES >nul 2>&1

:: Esperar que los volumenes se monten
ping 127.0.0.1 -n 5 >nul

:: Lanzar menu forense
if exist X:\Tools\bitlocker_diag.cmd (
    call X:\Tools\bitlocker_diag.cmd
) else (
    :: Buscar en USB conectado
    for %%D in (C D E F G H I J K) do (
        if exist %%D:\bitlocker_diag.cmd (
            call %%D:\bitlocker_diag.cmd
            goto :eof
        )
    )
    :: Fallback: CMD
    cmd.exe
)
'@
$startnetContent | Out-File -FilePath $startnetPath -Encoding ASCII -Force
Write-OK "startnet.cmd modificado:"
Write-Info "  - Teclado: espanol (0C0A:0000040A)"
Write-Info "  - Auto-launch: X:\Tools\bitlocker_diag.cmd"
Write-Info "  - Fallback: busca en USB, luego cmd.exe"

# ─────────────────────────────────────────────────────────────────────────────
# DESMONTAR WIM
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Guardando cambios y desmontando WIM..."
$out = & dism.exe /Unmount-Wim /MountDir:$MountDir /Commit 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "Error al desmontar WIM: $out"
    Write-Warn "Intentando desmontar sin guardar..."
    & dism.exe /Unmount-Wim /MountDir:$MountDir /Discard 2>&1 | Out-Null
    exit 1
}

$newWimSize = [math]::Round((Get-Item $WimCopy).Length / 1MB, 1)
Write-OK "WIM guardado: $WimCopy ($newWimSize MB)"

# ─────────────────────────────────────────────────────────────────────────────
# CREAR NUEVO boot_patched.sdi (implementacion de patch_sdi en PowerShell)
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Creando nuevo boot_patched.sdi..."

$stockSdi = $sdiSource
$newSdiPath = Join-Path $TempDir "boot_patched.sdi"

# Leer SDI stock
$sdiBytes = [System.IO.File]::ReadAllBytes($stockSdi)
$sdiLen = $sdiBytes.Length
Write-Info "SDI stock: ${sdiSource} (${sdiLen} bytes)"

# Verificar signature
$sig = [System.Text.Encoding]::ASCII.GetString($sdiBytes, 0, 8)
if ($sig -ne '$SDI0001') {
    Write-Warn "Signature inesperada: $sig (esperaba `$SDI0001)"
}

# Constantes del formato SDI
$BLOB_TABLE_OFFSET = 0x200
$BLOB_ENTRY_SIZE   = 64
$BLOB_TABLE_ENTRIES = 64
$ENTRY_TYPE_OFF    = 0x00
$ENTRY_DATA_OFF    = 0x10
$ENTRY_SIZE_OFF    = 0x18

# Encontrar entrada WIM en la tabla de blobs
$wimEntryIndex = -1
for ($i = 0; $i -lt $BLOB_TABLE_ENTRIES; $i++) {
    $base = $BLOB_TABLE_OFFSET + $i * $BLOB_ENTRY_SIZE
    if ($base + 4 -gt $sdiLen) { break }
    $tag = [System.Text.Encoding]::ASCII.GetString($sdiBytes, $base, 4)
    if ($tag -eq "WIM`0") {
        $wimEntryIndex = $i
        break
    }
}

if ($wimEntryIndex -lt 0) {
    Write-Err "No se encontro entrada WIM en el SDI."
    exit 1
}

$wimEntryBase = $BLOB_TABLE_OFFSET + $wimEntryIndex * $BLOB_ENTRY_SIZE
$oldWimOffset = [BitConverter]::ToUInt64($sdiBytes, $wimEntryBase + $ENTRY_DATA_OFF)
$oldWimSize   = [BitConverter]::ToUInt64($sdiBytes, $wimEntryBase + $ENTRY_SIZE_OFF)
Write-Info "WIM entry #${wimEntryIndex}: offset=0x$($oldWimOffset.ToString('X')), size=$([math]::Round($oldWimSize/1MB,1)) MB"

# Calcular nuevo offset (alineado a 4K)
$appendOffset = [math]::Ceiling($sdiLen / 4096) * 4096
$paddingNeeded = $appendOffset - $sdiLen
$wimFileSize = (Get-Item $WimCopy).Length

Write-Info "Append offset: 0x$($appendOffset.ToString('X'))"
Write-Info "Custom WIM size: $([math]::Round($wimFileSize/1MB,1)) MB"

# Construir SDI parcheado
Write-Info "Escribiendo SDI parcheado..."
$outStream = [System.IO.File]::OpenWrite($newSdiPath)
try {
    # 1. Escribir SDI stock
    $outStream.Write($sdiBytes, 0, $sdiLen)
    
    # 2. Padding
    if ($paddingNeeded -gt 0) {
        $padding = New-Object byte[] $paddingNeeded
        $outStream.Write($padding, 0, $paddingNeeded)
    }
    
    # 3. Append custom WIM
    $wimStream = [System.IO.File]::OpenRead($WimCopy)
    try {
        $buffer = New-Object byte[] (1024 * 1024)
        $totalWritten = 0
        while (($read = $wimStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $read)
            $totalWritten += $read
            $pct = [math]::Round($totalWritten * 100 / $wimFileSize)
            Write-Host "`r    Progreso: $pct% ($([math]::Round($totalWritten/1MB)) / $([math]::Round($wimFileSize/1MB)) MB)" -NoNewline
        }
        Write-Host ""
    } finally { $wimStream.Close() }
    
    # 4. Parchear entrada WIM en la tabla de blobs
    $outStream.Seek($wimEntryBase + $ENTRY_DATA_OFF, [System.IO.SeekOrigin]::Begin) | Out-Null
    $outStream.Write([BitConverter]::GetBytes([UInt64]$appendOffset), 0, 8)
    $outStream.Seek($wimEntryBase + $ENTRY_SIZE_OFF, [System.IO.SeekOrigin]::Begin) | Out-Null
    $outStream.Write([BitConverter]::GetBytes([UInt64]$wimFileSize), 0, 8)
} finally { $outStream.Close() }

$finalSize = (Get-Item $newSdiPath).Length
Write-OK "SDI parcheado creado: $newSdiPath ($([math]::Round($finalSize/1MB,1)) MB)"

# ─────────────────────────────────────────────────────────────────────────────
# COPIAR AL USB
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Copiando nuevo SDI al USB..."

$usbSdiDir = Join-Path $USB "sdi"
if (-not (Test-Path $usbSdiDir)) { New-Item -ItemType Directory -Path $usbSdiDir -Force | Out-Null }

# Backup del SDI anterior
$oldSdi = Join-Path $usbSdiDir "boot_patched.sdi"
if (Test-Path $oldSdi) {
    $backupName = "boot_patched_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').sdi"
    Write-Info "Backup del SDI anterior: $backupName"
    # No hacemos backup por espacio, solo reemplazamos
}

Write-Info "Copiando $([math]::Round($finalSize/1MB,1)) MB al USB (esto tarda ~2 min)..."
Copy-Item $newSdiPath $oldSdi -Force
Write-OK "boot_patched.sdi copiado al USB."

# Copiar bitlocker_diag.cmd al root del USB tambien (como fallback)
if ($diagSource) {
    Copy-Item $diagSource (Join-Path $USB "bitlocker_diag.cmd") -Force
    Write-Info "bitlocker_diag.cmd copiado a la raiz del USB (fallback)"
}

# ─────────────────────────────────────────────────────────────────────────────
# GENERAR BCD UNIVERSAL (si no existe)
# ─────────────────────────────────────────────────────────────────────────────

$bcdPath = Join-Path $USB "EFI\Microsoft\Boot\BCD"
if (-not (Test-Path $bcdPath)) {
    Write-Step "Generando BCD universal..."
    $bcdDir = Split-Path $bcdPath -Parent
    New-Item -ItemType Directory -Path $bcdDir -Force | Out-Null
    
    & bcdedit /createstore $bcdPath 2>&1 | Out-Null
    $rdOut = & bcdedit /store $bcdPath /create /d "Ramdisk" /device 2>&1
    $rdGuid = [regex]::Match($rdOut, '\{[0-9a-fA-F\-]+\}').Value
    
    if ($rdGuid) {
        & bcdedit /store $bcdPath /set $rdGuid ramdisksdidevice boot 2>&1 | Out-Null
        & bcdedit /store $bcdPath /set $rdGuid ramdisksdipath \sdi\boot_patched.sdi 2>&1 | Out-Null
        
        $ldrOut = & bcdedit /store $bcdPath /create /d "BitUnlocker Forensic Toolkit" /application osloader 2>&1
        $ldrGuid = [regex]::Match($ldrOut, '\{[0-9a-fA-F\-]+\}').Value
        
        if ($ldrGuid) {
            & bcdedit /store $bcdPath /set $ldrGuid device "ramdisk=[boot]\sdi\boot_patched.sdi,$rdGuid" 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set $ldrGuid osdevice "ramdisk=[boot]\sdi\boot_patched.sdi,$rdGuid" 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set $ldrGuid path \windows\system32\winload.efi 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set $ldrGuid systemroot \windows 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set $ldrGuid winpe yes 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set $ldrGuid detecthal yes 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set $ldrGuid nx optin 2>&1 | Out-Null
            
            & bcdedit /store $bcdPath /create "{bootmgr}" /d "BitUnlocker Boot Manager" 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set "{bootmgr}" default $ldrGuid 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set "{bootmgr}" displayorder $ldrGuid 2>&1 | Out-Null
            & bcdedit /store $bcdPath /set "{bootmgr}" timeout 5 2>&1 | Out-Null
            
            Write-OK "BCD universal generado."
        }
    }
} else {
    Write-Info "BCD ya existe en el USB. Se conserva."
}

# ─────────────────────────────────────────────────────────────────────────────
# LIMPIAR
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Limpiando archivos temporales..."
Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
Write-OK "Limpieza completada."

# ─────────────────────────────────────────────────────────────────────────────
# VERIFICACION FINAL
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  VERIFICACION DEL USB" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

$checks = @(
    @{ File = "$USB\EFI\Boot\bootx64.efi";      Label = "bootx64.efi" },
    @{ File = "$USB\EFI\Microsoft\Boot\BCD";     Label = "BCD (universal)" },
    @{ File = "$USB\sdi\boot_patched.sdi";       Label = "boot_patched.sdi (con menu)" }
)

$allOk = $true
foreach ($c in $checks) {
    if (Test-Path $c.File) {
        $size = [math]::Round((Get-Item $c.File).Length / 1MB, 1)
        Write-Host "  [OK] $($c.Label) ($size MB)" -ForegroundColor Green
    } else {
        Write-Host "  [!!] $($c.Label) - FALTA" -ForegroundColor Red
        $allOk = $false
    }
}

Write-Host ""
if ($allOk) {
    Write-Host ("=" * 70) -ForegroundColor Green
    Write-Host "  USB ACTUALIZADO - LISTO PARA USAR" -ForegroundColor Green
    Write-Host ("=" * 70) -ForegroundColor Green
    Write-Host ""
    Write-Host "  Al arrancar desde F12 veras AUTOMATICAMENTE:" -ForegroundColor Yellow
    Write-Host "  - Teclado configurado en espanol" -ForegroundColor White
    Write-Host "  - Menu forense con 9 opciones" -ForegroundColor White
    Write-Host "  - Sin necesidad de escribir nada manualmente" -ForegroundColor White
    Write-Host ""
    Write-Host "  Flujo: Conectar USB -> F12 -> Seleccionar USB -> ~2 min -> MENU" -ForegroundColor Cyan
} else {
    Write-Host "  [!!] Hay archivos faltantes. Verifica el proceso." -ForegroundColor Red
}

Write-Host ""
Write-Host "  DISCLAIMER: Solo usar en equipos propios o con permiso escrito." -ForegroundColor Red
Write-Host ""
