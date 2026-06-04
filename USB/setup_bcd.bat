@echo off
setlocal enabledelayedexpansion
title BitUnlocker - Configuracion automatica de BCD
color 1F
cls

echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║        BITUNLOCKER - Configuracion automatica de BCD                ║
echo  ║        JernelSystems Research - Solo equipos propios                ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  Este script detecta automaticamente los datos de arranque del equipo,
echo  genera el BCD modificado y lo copia a tu USB.
echo.
echo  ════════════════════════════════════════════════════════════════════════
echo  PASO 1: Seleccionar la letra de tu USB
echo  ════════════════════════════════════════════════════════════════════════
echo.
echo  Unidades disponibles:
echo  ────────────────────────────────────────────────────────────────────────

:: Listar unidades disponibles con etiqueta
for %%D in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    vol %%D: 2>nul | findstr /i "volumen\|volume" >nul 2>&1
    if not errorlevel 1 (
        for /f "tokens=*" %%V in ('vol %%D: 2^>nul ^| findstr /i "volumen\|volume"') do (
            echo    [%%D]  %%V
        )
    )
)

echo  ────────────────────────────────────────────────────────────────────────
echo.
set /p USB_LETRA="  Escribe la letra de tu USB (ej: E): "
set USB_LETRA=!USB_LETRA: =!

:: Validar que la letra tiene contenido
if "!USB_LETRA!"=="" (
    echo  [!] No escribiste ninguna letra. Saliendo.
    pause
    exit /b 1
)

:: Verificar que la unidad existe
vol !USB_LETRA!: >nul 2>&1
if errorlevel 1 (
    echo  [X] La unidad !USB_LETRA!: no existe o no esta disponible.
    pause
    exit /b 1
)

:: Verificar que el USB tiene la estructura correcta
if not exist "!USB_LETRA!:\EFI\Boot\bootx64.efi" (
    echo  [X] No se encontro bootx64.efi en !USB_LETRA!:\EFI\Boot\
    echo      Asegurate de que el USB tiene el contenido del repositorio.
    pause
    exit /b 1
)

echo.
echo  [+] USB seleccionado: !USB_LETRA!:
echo.
echo  ════════════════════════════════════════════════════════════════════════
echo  PASO 2: Exportando BCD del equipo actual...
echo  ════════════════════════════════════════════════════════════════════════
echo.

:: Exportar BCD al USB
bcdedit /export "!USB_LETRA!:\BCD_modded" >nul 2>&1
if errorlevel 1 (
    echo  [X] Error al exportar el BCD. Verifica que estas en WinRE como Admin.
    pause
    exit /b 1
)
echo  [+] BCD exportado correctamente.

echo.
echo  ════════════════════════════════════════════════════════════════════════
echo  PASO 3: Buscando GUID de Windows Recovery automaticamente...
echo  ════════════════════════════════════════════════════════════════════════
echo.

:: Guardar salida de bcdedit en archivo temporal
bcdedit /store "!USB_LETRA!:\BCD_modded" /enum all > "%TEMP%\bcd_enum.txt" 2>&1

:: Buscar el GUID de la entrada que tiene ramdisksdipath
set TARGET_GUID=
set CURRENT_GUID=
set FOUND_SDI=0

for /f "usebackq tokens=*" %%L in ("%TEMP%\bcd_enum.txt") do (
    set LINE=%%L

    :: Detectar inicio de una nueva entrada (linea con identificador {...)
    echo !LINE! | findstr /r "^{.*}" >nul 2>&1
    if not errorlevel 1 (
        :: Si la entrada anterior tenia ramdisksdipath, ya tenemos el GUID
        if "!FOUND_SDI!"=="1" (
            if "!TARGET_GUID!"=="" set TARGET_GUID=!CURRENT_GUID!
        )
        set FOUND_SDI=0
        :: Extraer GUID de la linea
        for /f "tokens=1" %%G in ("!LINE!") do set CURRENT_GUID=%%G
    )

    :: Detectar si esta entrada tiene ramdisksdipath (es Windows Recovery)
    echo !LINE! | findstr /i "ramdisksdipath" >nul 2>&1
    if not errorlevel 1 (
        set FOUND_SDI=1
    )
)

:: Verificar la ultima entrada
if "!FOUND_SDI!"=="1" (
    if "!TARGET_GUID!"=="" set TARGET_GUID=!CURRENT_GUID!
)

:: Si no encontramos por ramdisksdipath, buscar por descripcion "Windows Recovery"
if "!TARGET_GUID!"=="" (
    echo  [!] Buscando por descripcion "Windows Recovery"...
    set PREV_GUID=
    set CURRENT_GUID=

    for /f "usebackq tokens=*" %%L in ("%TEMP%\bcd_enum.txt") do (
        set LINE=%%L

        echo !LINE! | findstr /r "^{.*}" >nul 2>&1
        if not errorlevel 1 (
            for /f "tokens=1" %%G in ("!LINE!") do set CURRENT_GUID=%%G
        )

        echo !LINE! | findstr /i "Windows Recovery Environment" >nul 2>&1
        if not errorlevel 1 (
            set TARGET_GUID=!CURRENT_GUID!
        )
    )
)

if "!TARGET_GUID!"=="" (
    echo  [X] No se encontro automaticamente la entrada de Windows Recovery.
    echo.
    echo  Contenido del BCD:
    type "%TEMP%\bcd_enum.txt" | findstr /i "description\|{" | head -30
    echo.
    set /p TARGET_GUID="  Introduce el GUID manualmente (ej: {abc-123-...}): "
)

if "!TARGET_GUID!"=="" (
    echo  [X] No se pudo determinar el GUID. Saliendo.
    del "%TEMP%\bcd_enum.txt" >nul 2>&1
    pause
    exit /b 1
)

echo  [+] GUID encontrado: !TARGET_GUID!

echo.
echo  ════════════════════════════════════════════════════════════════════════
echo  PASO 4: Modificando BCD...
echo  ════════════════════════════════════════════════════════════════════════
echo.

:: Modificar la ruta del winload para que falle y caiga a WinRE
bcdedit /store "!USB_LETRA!:\BCD_modded" /set {default} path \WINDOWS\system32\winload_DOESNOTEXIST.efi >nul 2>&1
if errorlevel 1 (
    echo  [!] Advertencia: no se pudo modificar {default} path. Continuando...
) else (
    echo  [+] Ruta winload modificada para forzar WinRE.
)

:: Apuntar el ramdisk del WinRE a nuestro SDI
bcdedit /store "!USB_LETRA!:\BCD_modded" /set "!TARGET_GUID!" ramdisksdidevice boot >nul 2>&1
if errorlevel 1 (
    echo  [X] Error al modificar ramdisksdidevice.
    del "%TEMP%\bcd_enum.txt" >nul 2>&1
    pause
    exit /b 1
)
echo  [+] ramdisksdidevice = boot

bcdedit /store "!USB_LETRA!:\BCD_modded" /set "!TARGET_GUID!" ramdisksdipath \sdi\boot_patched.sdi >nul 2>&1
if errorlevel 1 (
    echo  [X] Error al modificar ramdisksdipath.
    del "%TEMP%\bcd_enum.txt" >nul 2>&1
    pause
    exit /b 1
)
echo  [+] ramdisksdipath = \sdi\boot_patched.sdi

echo.
echo  ════════════════════════════════════════════════════════════════════════
echo  PASO 5: Copiando BCD al lugar correcto en el USB...
echo  ════════════════════════════════════════════════════════════════════════
echo.

:: Crear directorio si no existe
if not exist "!USB_LETRA!:\EFI\Microsoft\Boot" (
    mkdir "!USB_LETRA!:\EFI\Microsoft\Boot" >nul 2>&1
)

:: Renombrar BCD_modded → BCD y moverlo a la ubicacion correcta
move /y "!USB_LETRA!:\BCD_modded" "!USB_LETRA!:\EFI\Microsoft\Boot\BCD" >nul 2>&1
if errorlevel 1 (
    echo  [X] Error al mover el BCD. Intentando copia directa...
    copy /y "!USB_LETRA!:\BCD_modded" "!USB_LETRA!:\EFI\Microsoft\Boot\BCD" >nul 2>&1
    del "!USB_LETRA!:\BCD_modded" >nul 2>&1
)

:: Verificar resultado
if exist "!USB_LETRA!:\EFI\Microsoft\Boot\BCD" (
    echo  [+] BCD copiado exitosamente.
) else (
    echo  [X] El BCD no se pudo guardar en el USB.
    del "%TEMP%\bcd_enum.txt" >nul 2>&1
    pause
    exit /b 1
)

:: Limpiar temporal
del "%TEMP%\bcd_enum.txt" >nul 2>&1

echo.
echo  ════════════════════════════════════════════════════════════════════════
echo  PASO 6: Verificando estructura del USB...
echo  ════════════════════════════════════════════════════════════════════════
echo.

set ERRORES=0

if exist "!USB_LETRA!:\EFI\Boot\bootx64.efi" (
    echo  [OK] EFI\Boot\bootx64.efi
) else (
    echo  [!!] EFI\Boot\bootx64.efi  - NO ENCONTRADO
    set ERRORES=1
)

if exist "!USB_LETRA!:\EFI\Microsoft\Boot\BCD" (
    echo  [OK] EFI\Microsoft\Boot\BCD
) else (
    echo  [!!] EFI\Microsoft\Boot\BCD  - NO ENCONTRADO
    set ERRORES=1
)

if exist "!USB_LETRA!:\sdi\boot_patched.sdi" (
    echo  [OK] sdi\boot_patched.sdi
) else (
    echo  [!!] sdi\boot_patched.sdi  - NO ENCONTRADO
    set ERRORES=1
)

echo.
if "!ERRORES!"=="0" (
    color 2F
    echo  ╔══════════════════════════════════════════════════════════════════════╗
    echo  ║   ✅  USB LISTO - Puedes arrancar desde el desde este USB           ║
    echo  ╠══════════════════════════════════════════════════════════════════════╣
    echo  ║   1. Retira el USB con seguridad                                    ║
    echo  ║   2. Reinicia el equipo                                             ║
    echo  ║   3. Arranca desde el USB (F12 / F9 / "Usar un dispositivo")        ║
    echo  ║   4. Espera ~2 minutos mientras carga el SDI                        ║
    echo  ║   5. Aparecera el menu forense automaticamente                      ║
    echo  ╚══════════════════════════════════════════════════════════════════════╝
) else (
    color 4F
    echo  [!!] Hay archivos faltantes. Verifica que el USB tiene el contenido
    echo       completo del repositorio antes de ejecutar este script.
)

echo.
pause
endlocal
