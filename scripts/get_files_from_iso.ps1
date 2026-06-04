#Requires -RunAsAdministrator
<#
.SYNOPSIS
    get_files_from_iso.ps1 - Extrae WinRE.wim y boot.sdi de una ISO de Windows 11.
    Estos archivos son necesarios para build_custom_winre.ps1 y patch_sdi.py.

.DESCRIPTION
    Este script:
    1. Monta la ISO de Windows 11
    2. Extrae WinRE.wim desde el boot.wim (indice 2 = Windows Setup PE)
    3. Extrae boot.sdi desde la ISO
    4. Desmonta la ISO
    5. Muestra las rutas de los archivos extraidos

.PARAMETER IsoPath
    Ruta a la ISO de Windows 11. Ejemplo: C:\Win11.iso

.PARAMETER OutputDir
    Directorio donde guardar los archivos extraidos. Por defecto: directorio actual.

.EXAMPLE
    .\get_files_from_iso.ps1 -IsoPath "C:\Win11_23H2.iso"

.EXAMPLE
    .\get_files_from_iso.ps1 -IsoPath "D:\ISOs\Win11.iso" -OutputDir "C:\BitUnlocker_Files"

.NOTES
    Si no tienes una ISO, descargala desde:
    https://www.microsoft.com/es-es/software-download/windows11
    (Opcion: "Descargar imagen de disco de Windows 11 (ISO)")
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$IsoPath,

    [string]$OutputDir = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
# FUNCIONES
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step  { param([string]$M); Write-Host "[*] $M" -ForegroundColor Green }
function Write-Info  { param([string]$M); Write-Host "    $M" -ForegroundColor Gray }
function Write-Warn  { param([string]$M); Write-Host "[!] $M" -ForegroundColor Yellow }
function Write-Err   { param([string]$M); Write-Host "[X] $M" -ForegroundColor Red }
function Write-OK    { param([string]$M); Write-Host "[+] $M" -ForegroundColor Cyan }

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -gt 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -gt 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N0} KB" -f ($Bytes / 1KB)
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDACIONES
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  BitUnlocker - Extractor de WinRE.wim y boot.sdi desde ISO" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

# Verificar ISO
if (-not (Test-Path $IsoPath)) {
    Write-Err "ISO no encontrada: $IsoPath"
    exit 1
}

$isoItem = Get-Item $IsoPath
Write-Step "ISO: $($isoItem.Name)"
Write-Info "Tamano: $(Format-Size $isoItem.Length)"
Write-Info "Ruta: $IsoPath"

# Preparar directorio de salida
$OutputDir = (New-Item -ItemType Directory -Path $OutputDir -Force).FullName
Write-Step "Directorio de salida: $OutputDir"

# Directorio temporal para montar boot.wim
$TempMount = "C:\WIM_ISO_Mount_Temp"
if (Test-Path $TempMount) {
    & dism.exe /Unmount-Wim /MountDir:$TempMount /Discard 2>$null | Out-Null
    Remove-Item -Recurse -Force $TempMount -ErrorAction SilentlyContinue
}

$IsoDriveLetter = $null

# ─────────────────────────────────────────────────────────────────────────────
# PASO 1: MONTAR ISO
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Montando ISO..."
try {
    $mountResult = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $IsoDriveLetter = ($mountResult | Get-Volume).DriveLetter
    Write-Info "ISO montada en: ${IsoDriveLetter}:\"
} catch {
    Write-Err "Error al montar ISO: $_"
    Write-Warn "Intentando con PowerShell directo..."
    try {
        $mountResult = Mount-DiskImage -ImagePath (Resolve-Path $IsoPath).Path -PassThru
        $IsoDriveLetter = ($mountResult | Get-Volume).DriveLetter
        Write-Info "ISO montada en: ${IsoDriveLetter}:\"
    } catch {
        Write-Err "No se pudo montar la ISO. Verifica que el archivo no este corrupto."
        exit 1
    }
}

$IsoRoot = "${IsoDriveLetter}:\"

# ─────────────────────────────────────────────────────────────────────────────
# PASO 2: LISTAR CONTENIDO RELEVANTE
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Explorando contenido de la ISO..."

$bootWimPath = Join-Path $IsoRoot "sources\boot.wim"
$bootSdiPath = Join-Path $IsoRoot "boot\boot.sdi"
$installWimPath = Join-Path $IsoRoot "sources\install.wim"
$installEsdPath = Join-Path $IsoRoot "sources\install.esd"

Write-Info "boot.wim   : $(if (Test-Path $bootWimPath)   { Format-Size (Get-Item $bootWimPath).Length }   else { 'NO ENCONTRADO' })"
Write-Info "boot.sdi   : $(if (Test-Path $bootSdiPath)   { Format-Size (Get-Item $bootSdiPath).Length }   else { 'NO ENCONTRADO' })"
Write-Info "install.wim: $(if (Test-Path $installWimPath) { Format-Size (Get-Item $installWimPath).Length } else { 'NO ENCONTRADO' })"
Write-Info "install.esd: $(if (Test-Path $installEsdPath) { Format-Size (Get-Item $installEsdPath).Length } else { 'NO ENCONTRADO' })"

# ─────────────────────────────────────────────────────────────────────────────
# PASO 3: EXTRAER boot.sdi
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Extrayendo boot.sdi..."

$outSdi = Join-Path $OutputDir "boot.sdi"

if (Test-Path $bootSdiPath) {
    Copy-Item -Path $bootSdiPath -Destination $outSdi -Force
    Write-OK "boot.sdi extraido: $outSdi ($(Format-Size (Get-Item $outSdi).Length))"
} else {
    Write-Warn "boot.sdi no encontrado en boot\boot.sdi de la ISO."
    Write-Warn "Buscando en otras ubicaciones..."
    $sdiFound = Get-ChildItem -Path $IsoRoot -Recurse -Filter "boot.sdi" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sdiFound) {
        Copy-Item -Path $sdiFound.FullName -Destination $outSdi -Force
        Write-OK "boot.sdi encontrado y extraido desde: $($sdiFound.FullName)"
    } else {
        Write-Err "No se encontro boot.sdi en la ISO."
        Write-Warn "Puedes obtenerlo desde una instalacion de Windows existente:"
        Write-Warn "  Ruta: C:\Windows\Boot\DVD\EFI\en-US\boot.sdi"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PASO 4: EXTRAER WinRE.wim desde boot.wim
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Extrayendo WinRE.wim desde boot.wim..."

if (-not (Test-Path $bootWimPath)) {
    Write-Err "boot.wim no encontrado en la ISO."
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    exit 1
}

# Ver indices del boot.wim
Write-Info "Indices en boot.wim:"
$wimInfoOutput = & dism.exe /Get-WimInfo /WimFile:$bootWimPath 2>&1
$wimInfoOutput | Where-Object { $_ -match "Index|Name|Description" } | ForEach-Object {
    Write-Info "  $_"
}

# boot.wim suele tener:
#   Index 1 = Windows PE (setup)
#   Index 2 = Windows Setup (contiene WinRE.wim dentro)
# WinRE.wim esta embebido en el indice 2

New-Item -ItemType Directory -Path $TempMount -Force | Out-Null

# Intentar indice 2 primero, luego indice 1
$winreFound = $false
foreach ($idx in @(2, 1)) {
    Write-Info "Montando boot.wim indice $idx..."
    $mountOut = & dism.exe /Mount-Wim /WimFile:$bootWimPath /Index:$idx /MountDir:$TempMount /ReadOnly 2>&1
    if ($LASTEXITCODE -eq 0) {
        # Buscar WinRE.wim dentro del montaje
        $winreInWim = Get-ChildItem -Path $TempMount -Recurse -Filter "WinRE.wim" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($winreInWim) {
            $outWinre = Join-Path $OutputDir "custom_winre_base.wim"
            Write-Info "WinRE.wim encontrado en: $($winreInWim.FullName)"
            Copy-Item -Path $winreInWim.FullName -Destination $outWinre -Force
            Write-OK "WinRE.wim extraido: $outWinre ($(Format-Size (Get-Item $outWinre).Length))"
            $winreFound = $true
        }
        # Desmontar
        & dism.exe /Unmount-Wim /MountDir:$TempMount /Discard 2>&1 | Out-Null
        if ($winreFound) { break }
    } else {
        Write-Warn "No se pudo montar indice $idx"
        & dism.exe /Unmount-Wim /MountDir:$TempMount /Discard 2>$null | Out-Null
    }
}

if (-not $winreFound) {
    Write-Warn "WinRE.wim no encontrado dentro de boot.wim."
    Write-Step "Buscando WinRE.wim en el sistema actual..."
    $sysWinre = @(
        "$env:SystemRoot\System32\Recovery\WinRE.wim",
        "C:\Recovery\WindowsRE\WinRE.wim"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($sysWinre) {
        $outWinre = Join-Path $OutputDir "custom_winre_base.wim"
        Copy-Item -Path $sysWinre -Destination $outWinre -Force
        Write-OK "WinRE.wim del sistema copiado: $outWinre ($(Format-Size (Get-Item $outWinre).Length))"
        $winreFound = $true
    } else {
        Write-Err "No se encontro WinRE.wim. Ejecuta 'reagentc /info' para localizar la particion de recuperacion."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# PASO 5: DESMONTAR ISO Y LIMPIAR
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Desmontando ISO..."
Dismount-DiskImage -ImagePath $IsoPath | Out-Null
Write-Info "ISO desmontada."

if (Test-Path $TempMount) {
    Remove-Item -Recurse -Force $TempMount -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────────────────────────────
# RESUMEN FINAL
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  ARCHIVOS EXTRAIDOS" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

$sdiOk   = Test-Path (Join-Path $OutputDir "boot.sdi")
$winreOk = Test-Path (Join-Path $OutputDir "custom_winre_base.wim")

if ($sdiOk) {
    Write-Host "  [OK] boot.sdi             : $(Join-Path $OutputDir 'boot.sdi')" -ForegroundColor Green
} else {
    Write-Host "  [!!] boot.sdi             : NO EXTRAIDO" -ForegroundColor Red
}

if ($winreOk) {
    Write-Host "  [OK] custom_winre_base.wim: $(Join-Path $OutputDir 'custom_winre_base.wim')" -ForegroundColor Green
} else {
    Write-Host "  [!!] custom_winre_base.wim: NO EXTRAIDO" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Proximos pasos:" -ForegroundColor Yellow

if ($winreOk) {
    Write-Host "  1. Modificar el WIM con el menu interactivo:" -ForegroundColor White
    Write-Host "     .\build_custom_winre.ps1 -WimPath '$(Join-Path $OutputDir 'custom_winre_base.wim')' -StockSdi '$(Join-Path $OutputDir 'boot.sdi')'" -ForegroundColor Gray
}

Write-Host "  2. El script generara: boot_patched_custom.sdi" -ForegroundColor White
Write-Host "  3. Copia el SDI a: USB\sdi\boot_patched.sdi" -ForegroundColor White
Write-Host ""
Write-Host "  DISCLAIMER: Solo usar en equipos propios o con permiso explicito." -ForegroundColor Red
Write-Host ""
