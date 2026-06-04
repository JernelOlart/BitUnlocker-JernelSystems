#Requires -RunAsAdministrator
<#
.SYNOPSIS
    build_custom_winre.ps1 - Monta y modifica un WinRE.wim para investigacion de seguridad BitLocker.
    Agrega scripts de diagnostico que se ejecutan automaticamente al arrancar el WinRE parcheado.

.DESCRIPTION
    Este script:
    1. Monta el WinRE.wim con DISM
    2. Inyecta un script de diagnostico BitLocker (bitlocker_diag.cmd)
    3. Modifica startnet.cmd para ejecutar el diagnostico al arrancar
    4. Desmonta y guarda el WIM modificado
    5. (Opcional) Llama a patch_sdi.py para generar el boot_patched.sdi final

    USO SOLO EN SISTEMAS PROPIOS O CON PERMISO EXPLICITO ESCRITO.

.PARAMETER WimPath
    Ruta al WinRE.wim original. Por defecto busca en el sistema actual.

.PARAMETER OutputWim
    Ruta de salida para el WIM modificado.

.PARAMETER MountDir
    Directorio temporal de montaje. Por defecto: C:\WinRE_Mount

.PARAMETER ExtraToolsDir
    Directorio opcional con herramientas adicionales a copiar dentro del WIM.
    Se copian a X:\Tools\ dentro del WinRE.

.PARAMETER StockSdi
    (Opcional) Ruta al boot.sdi original para generar el SDI final con patch_sdi.py

.PARAMETER PythonExe
    (Opcional) Ruta al ejecutable de Python. Por defecto: python

.EXAMPLE
    # Uso basico (usa WinRE del sistema actual)
    .\build_custom_winre.ps1

.EXAMPLE
    # Con WIM especifico y herramientas extra
    .\build_custom_winre.ps1 -WimPath "D:\sources\boot.wim" -ExtraToolsDir "C:\MisHerramientas"

.EXAMPLE
    # Generar SDI completo de una vez
    .\build_custom_winre.ps1 -StockSdi "C:\boot.sdi"
#>

param(
    [string]$WimPath      = "",
    [string]$OutputWim    = ".\custom_winre.wim",
    [string]$MountDir     = "C:\WinRE_Mount",
    [string]$ExtraToolsDir = "",
    [string]$StockSdi     = "",
    [string]$PythonExe    = "python"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
# FUNCIONES AUXILIARES
# ─────────────────────────────────────────────────────────────────────────────

function Write-Banner {
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host "  BitUnlocker - Custom WinRE Builder" -ForegroundColor Cyan
    Write-Host "  Solo para investigacion de seguridad autorizada" -ForegroundColor Yellow
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Msg)
    Write-Host "[*] $Msg" -ForegroundColor Green
}

function Write-Info {
    param([string]$Msg)
    Write-Host "    $Msg" -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Msg)
    Write-Host "[!] $Msg" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Msg)
    Write-Host "[X] $Msg" -ForegroundColor Red
}

function Cleanup {
    param([string]$Dir)
    Write-Warn "Limpiando directorio de montaje: $Dir"
    try {
        $dismArgs = @("/Unmount-Wim", "/MountDir:$Dir", "/Discard")
        & dism.exe @dismArgs 2>$null | Out-Null
    } catch {}
    if (Test-Path $Dir) {
        Remove-Item -Recurse -Force $Dir -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# RUTA AL SCRIPT DE DIAGNOSTICO EXTERNO
# bitlocker_diag.cmd debe estar en la misma carpeta que este script
# ─────────────────────────────────────────────────────────────────────────────

$ExternalDiagScript = Join-Path $PSScriptRoot "bitlocker_diag.cmd"

if (-not (Test-Path $ExternalDiagScript)) {
    Write-Err "No se encontro bitlocker_diag.cmd en: $PSScriptRoot"
    Write-Err "Asegurate de que bitlocker_diag.cmd este en la misma carpeta que este script."
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# SCRIPT PRINCIPAL
# ─────────────────────────────────────────────────────────────────────────────

Write-Banner

# 1. Verificar privilegios de administrador
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Este script requiere privilegios de Administrador."
    Write-Err "Ejecuta PowerShell como Administrador e intenta de nuevo."
    exit 1
}

# 2. Localizar WinRE.wim si no se especifico
if ($WimPath -eq "") {
    Write-Step "Buscando WinRE.wim en el sistema..."

    $candidates = @(
        "$env:SystemRoot\System32\Recovery\WinRE.wim",
        "C:\Recovery\WindowsRE\WinRE.wim"
    )

    # Buscar en particiones de recuperacion
    $reagent = reagentc /info 2>$null
    if ($reagent) {
        $reagent | Select-String "WinRE Location" | ForEach-Object {
            if ($_ -match "harddisk(\d+)\\partition(\d+)\\(.+)$") {
                Write-Info "ReAgent reporto ubicacion: $_"
            }
        }
    }

    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $WimPath = $c
            Write-Info "Encontrado: $WimPath"
            break
        }
    }

    if ($WimPath -eq "") {
        Write-Err "No se encontro WinRE.wim automaticamente."
        Write-Err "Especifica la ruta con -WimPath 'C:\ruta\WinRE.wim'"
        Write-Err ""
        Write-Err "Opciones para obtener WinRE.wim:"
        Write-Err "  1. Desde ISO Windows 11: montar ISO -> sources\boot.wim (indice 2)"
        Write-Err "  2. Desde sistema actual: reagentc /info para localizar"
        Write-Err "  3. Extraer de: C:\Recovery\WindowsRE\WinRE.wim"
        exit 1
    }
}

Write-Step "WIM fuente: $WimPath"
$wimSize = (Get-Item $WimPath).Length / 1MB
Write-Info "Tamano: $([math]::Round($wimSize, 1)) MiB"

# 3. Preparar directorio de montaje
if (Test-Path $MountDir) {
    Write-Warn "El directorio de montaje ya existe: $MountDir"
    Write-Warn "Intentando limpiar montaje previo..."
    & dism.exe /Unmount-Wim /MountDir:$MountDir /Discard 2>$null | Out-Null
    Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $MountDir -Force | Out-Null
Write-Step "Directorio de montaje creado: $MountDir"

# 4. Obtener indices del WIM
Write-Step "Analizando indices del WIM..."
$wimInfo = & dism.exe /Get-WimInfo /WimFile:$WimPath 2>&1
$wimInfo | Where-Object { $_ -match "Index|Name" } | ForEach-Object {
    Write-Info $_
}

# Usar indice 1 por defecto (WinRE suele tener solo 1)
$wimIndex = 1

# 5. Montar el WIM
Write-Step "Montando WIM (indice $wimIndex)... esto puede tardar 1-2 minutos"
try {
    $dismMount = & dism.exe /Mount-Wim /WimFile:$WimPath /Index:$wimIndex /MountDir:$MountDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "DISM fallo al montar el WIM:"
        $dismMount | ForEach-Object { Write-Err "  $_" }
        Cleanup $MountDir
        exit 1
    }
    Write-Info "WIM montado exitosamente en $MountDir"
} catch {
    Write-Err "Error al montar WIM: $_"
    Cleanup $MountDir
    exit 1
}

# 6. Crear estructura de directorios dentro del WIM
Write-Step "Preparando estructura de directorios en el WIM..."

$toolsDir  = Join-Path $MountDir "Tools"
$scriptsIn = Join-Path $MountDir "Windows\System32"

New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
Write-Info "Creado: X:\Tools\ (herramientas forenses iran aqui)"

# 7. Copiar script de diagnostico BitLocker (menu interactivo completo)
Write-Step "Copiando script de diagnostico BitLocker con menu interactivo..."

$diagPath = Join-Path $toolsDir "bitlocker_diag.cmd"
Copy-Item -Path $ExternalDiagScript -Destination $diagPath -Force
$diagSize = [math]::Round((Get-Item $diagPath).Length / 1KB, 1)
Write-Info "Copiado: bitlocker_diag.cmd ($diagSize KB) -> X:\Tools\bitlocker_diag.cmd"
Write-Info "Incluye menu interactivo con: diagnostico, explorador, copiar archivos, backup perfiles, reporte"

# 8. Modificar startnet.cmd para ejecutar el diagnostico automaticamente
Write-Step "Modificando startnet.cmd para auto-ejecutar diagnostico..."

$startnetPath = Join-Path $MountDir "Windows\System32\startnet.cmd"

if (Test-Path $startnetPath) {
    $originalContent = Get-Content $startnetPath -Raw
    Write-Info "startnet.cmd original:"
    $originalContent -split "`n" | ForEach-Object { Write-Info "  $_" }
} else {
    $originalContent = "@echo off`r`nwpeinit`r`n"
    Write-Warn "startnet.cmd no encontrado, creando uno nuevo"
}

# Nuevo startnet.cmd que ejecuta el diagnostico
$newStartnet = @"
@echo off
wpeinit
:: ── BitUnlocker Forensic WinRE ──────────────────────────────────────────
:: Esperar a que los volumenes esten disponibles
ping 127.0.0.1 -n 3 > nul
:: Ejecutar diagnostico forense
X:\Tools\bitlocker_diag.cmd
"@

$newStartnet | Out-File -FilePath $startnetPath -Encoding ASCII -Force
Write-Info "startnet.cmd actualizado"

# 9. Copiar herramientas adicionales (si se especifico directorio)
if ($ExtraToolsDir -ne "" -and (Test-Path $ExtraToolsDir)) {
    Write-Step "Copiando herramientas adicionales desde: $ExtraToolsDir"
    $extraFiles = Get-ChildItem -Path $ExtraToolsDir -File
    foreach ($f in $extraFiles) {
        $dest = Join-Path $toolsDir $f.Name
        Copy-Item -Path $f.FullName -Destination $dest -Force
        $sizeMb = [math]::Round($f.Length / 1MB, 2)
        Write-Info "Copiado: $($f.Name) ($sizeMb MiB)"
    }
} elseif ($ExtraToolsDir -ne "") {
    Write-Warn "Directorio de herramientas no encontrado: $ExtraToolsDir (omitiendo)"
}

# 10. Mostrar resumen de lo que se inyecto
Write-Step "Contenido inyectado en el WIM:"
Get-ChildItem -Recurse $toolsDir | ForEach-Object {
    $rel = $_.FullName.Replace($MountDir, "X:")
    Write-Info $rel
}

# 11. Desmontar y guardar el WIM modificado
Write-Step "Desmontando y guardando cambios... (puede tardar varios minutos)"

$outputWimFull = (Resolve-Path -LiteralPath (Split-Path $OutputWim -Parent) -ErrorAction SilentlyContinue)
if (-not $outputWimFull) {
    $outputWimFull = (Get-Location).Path
}
$outputWimFull = Join-Path $outputWimFull (Split-Path $OutputWim -Leaf)

try {
    $dismUnmount = & dism.exe /Unmount-Wim /MountDir:$MountDir /Commit 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "DISM fallo al desmontar:"
        $dismUnmount | ForEach-Object { Write-Err "  $_" }
        Cleanup $MountDir
        exit 1
    }
} catch {
    Write-Err "Error al desmontar WIM: $_"
    Cleanup $MountDir
    exit 1
}

# Copiar el WIM modificado a la ubicacion de salida
Copy-Item -Path $WimPath -Destination $outputWimFull -Force
Write-Step "WIM modificado guardado en: $outputWimFull"

# Limpiar directorio de montaje
if (Test-Path $MountDir) {
    Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue
}

# 12. (Opcional) Generar SDI final con patch_sdi.py
if ($StockSdi -ne "") {
    if (-not (Test-Path $StockSdi)) {
        Write-Warn "boot.sdi no encontrado en: $StockSdi (omitiendo generacion de SDI)"
    } else {
        Write-Step "Generando boot_patched_custom.sdi con patch_sdi.py..."
        $patchScript = Join-Path $PSScriptRoot "patch_sdi.py"
        if (-not (Test-Path $patchScript)) {
            Write-Warn "patch_sdi.py no encontrado en $PSScriptRoot"
        } else {
            $sdiOutput = Join-Path (Split-Path $outputWimFull -Parent) "boot_patched_custom.sdi"
            & $PythonExe $patchScript --sdi $StockSdi --wim $outputWimFull -o $sdiOutput
            if ($LASTEXITCODE -eq 0) {
                Write-Step "SDI final generado: $sdiOutput"
                Write-Info "Copia este archivo a: USB\sdi\boot_patched.sdi"
            } else {
                Write-Warn "patch_sdi.py retorno error. Revisa la salida de arriba."
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# RESUMEN FINAL
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  COMPLETADO" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
Write-Host "  WIM modificado   : $outputWimFull" -ForegroundColor White
Write-Host ""
Write-Host "  Proximos pasos:" -ForegroundColor Yellow
Write-Host "  1. Usa el WIM modificado con patch_sdi.py:" -ForegroundColor White
Write-Host "     python patch_sdi.py --sdi boot.sdi --wim $outputWimFull -o boot_patched_custom.sdi" -ForegroundColor Gray
Write-Host "  2. Copia boot_patched_custom.sdi -> USB\sdi\boot_patched.sdi" -ForegroundColor White
Write-Host "  3. Sigue los pasos del README para modificar el BCD y arrancar" -ForegroundColor White
Write-Host ""
Write-Host "  Al arrancar el WinRE modificado veras el MENU INTERACTIVO:" -ForegroundColor Yellow
Write-Host "  [1] Diagnostico completo BitLocker" -ForegroundColor White
Write-Host "  [2] Ver protectores y claves de cifrado" -ForegroundColor White
Write-Host "  [3] Explorador de archivos interactivo" -ForegroundColor White
Write-Host "  [4] Copiar archivos / carpetas" -ForegroundColor White
Write-Host "  [5] Copia rapida de perfiles de usuario" -ForegroundColor White
Write-Host "  [6] Copiar archivos por tipo (docs, imgs, credenciales...)" -ForegroundColor White
Write-Host "  [7] Informacion del sistema y TPM" -ForegroundColor White
Write-Host "  [8] Guardar reporte completo" -ForegroundColor White
Write-Host "  [9] Shell interactivo avanzado" -ForegroundColor White
Write-Host ""
Write-Host "  DISCLAIMER: Solo usar en equipos propios o con permiso explicito." -ForegroundColor Red
Write-Host ""
