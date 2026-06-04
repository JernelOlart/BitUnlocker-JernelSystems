@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title BitLocker Forensic Toolkit - JernelSystems Research
color 1F

:: ─────────────────────────────────────────────────────────────────────────────
:: INICIALIZAR ENTORNO
:: ─────────────────────────────────────────────────────────────────────────────
echo Inicializando entorno WinPE...
wpeinit >nul 2>&1
ping 127.0.0.1 -n 3 >nul

:: Detectar volumen Windows automaticamente
set WIN_VOL=
for %%D in (C D E F G H I J) do (
    if exist %%D:\Windows\System32\cmd.exe (
        if "!WIN_VOL!"=="" set WIN_VOL=%%D
    )
)

:: Detectar volumen de usuarios
set USR_VOL=!WIN_VOL!

:: Detectar y configurar comando manage-bde con fallbacks
set BDE_CMD=manage-bde
if not exist "X:\Windows\System32\manage-bde.exe" (
    if exist "!WIN_VOL!:\Windows\System32\manage-bde.exe" (
        set BDE_CMD="!WIN_VOL!:\Windows\System32\manage-bde.exe"
    ) else if exist "!WIN_VOL!:\Windows\System32\manage-bde.wsf" (
        set BDE_CMD=cscript //nologo "!WIN_VOL!:\Windows\System32\manage-bde.wsf"
    )
)

goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: MENU PRINCIPAL
:: ─────────────────────────────────────────────────────────────────────────────
:MAIN_MENU
cls
color 1F
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║       BITLOCKER FORENSIC TOOLKIT  ^|  JernelSystems Research        ║
echo  ║           Equipo: %-20s  Fecha: %DATE%        ║
echo  ╠══════════════════════════════════════════════════════════════════════╣
echo  ║                                                                      ║
echo  ║   [1]  Diagnostico completo BitLocker                               ║
echo  ║   [2]  Ver protectores y claves de cifrado                          ║
echo  ║   [3]  Explorador de archivos interactivo                           ║
echo  ║   [4]  Copiar archivos / carpetas                                   ║
echo  ║   [5]  Copia de seguridad rapida (perfiles de usuario)              ║
echo  ║   [6]  Copiar archivos especificos por tipo                         ║
echo  ║   [7]  Informacion del sistema y TPM                                ║
echo  ║   [8]  Guardar reporte completo                                     ║
echo  ║   [9]  Abrir CMD interactivo avanzado                               ║
echo  ║   [0]  Salir                                                         ║
echo  ║                                                                      ║
if "!WIN_VOL!"=="" (
echo  ║   [!] ATENCION: No se detecto volumen Windows montado               ║
) else (
echo  ║   [+] Volumen Windows detectado: !WIN_VOL!:\                        ║
)
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
set /p OPCION="  Selecciona una opcion: "

if "!OPCION!"=="1" goto :DIAGNOSTICO_COMPLETO
if "!OPCION!"=="2" goto :VER_CLAVES
if "!OPCION!"=="3" goto :EXPLORADOR
if "!OPCION!"=="4" goto :COPIAR_ARCHIVOS
if "!OPCION!"=="5" goto :BACKUP_RAPIDO
if "!OPCION!"=="6" goto :COPIAR_POR_TIPO
if "!OPCION!"=="7" goto :INFO_SISTEMA
if "!OPCION!"=="8" goto :GUARDAR_REPORTE
if "!OPCION!"=="9" goto :CMD_AVANZADO
if "!OPCION!"=="0" goto :SALIR
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [1] DIAGNOSTICO COMPLETO BITLOCKER
:: ─────────────────────────────────────────────────────────────────────────────
:DIAGNOSTICO_COMPLETO
cls
color 1B
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [1] DIAGNOSTICO COMPLETO BITLOCKER                                ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  Estado de todos los volumenes:
echo  ────────────────────────────────────────────────────────────────────────
!BDE_CMD! -status
echo.
echo  ────────────────────────────────────────────────────────────────────────
echo  Certificado del Boot Manager:
echo  ────────────────────────────────────────────────────────────────────────
mountvol S: /s >nul 2>&1
if exist S:\EFI\Microsoft\Boot\bootmgfw.efi (
    echo  [+] Particion EFI montada. Archivo bootmgfw.efi encontrado:
    dir S:\EFI\Microsoft\Boot\bootmgfw.efi | findstr /v "^$"
    echo.
    echo  Para verificar certificado [requiere sigcheck.exe en X:\Tools\]:
    if exist X:\Tools\sigcheck.exe (
        echo  Ejecutando sigcheck...
        X:\Tools\sigcheck.exe -nobanner -i S:\EFI\Microsoft\Boot\bootmgfw.efi
    ) else (
        echo  sigcheck.exe no encontrado en X:\Tools\ - agrega Sysinternals sigcheck.exe
    )
) else (
    echo  [!] No se pudo acceder a la particion EFI.
    echo  Intenta manualmente: mountvol S: /s
)
echo.
echo  ────────────────────────────────────────────────────────────────────────
pause
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [2] VER PROTECTORES Y CLAVES
:: ─────────────────────────────────────────────────────────────────────────────
:VER_CLAVES
cls
color 1B
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [2] PROTECTORES DE CLAVE BITLOCKER                                ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  Buscando protectores en todos los volumenes...
echo  ────────────────────────────────────────────────────────────────────────
for %%D in (C D E F G H I J) do (
    vol %%D: >nul 2>&1
    if not errorlevel 1 (
        echo.
        echo  ┌─ Volumen %%D: ─────────────────────────────────────────────────────
        !BDE_CMD! -protectors -get %%D: 2>nul
        echo  └───────────────────────────────────────────────────────────────────
    )
)
echo.
echo  Tipos de protectores posibles:
echo    TPM           = Solo chip TPM (vulnerable a este ataque)
echo    TPMAndPIN     = TPM + PIN (NO vulnerable)
echo    RecoveryPassword = Clave de recuperacion de 48 digitos
echo    ExternalKey   = Archivo de clave USB
echo.
pause
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [3] EXPLORADOR DE ARCHIVOS INTERACTIVO
:: ─────────────────────────────────────────────────────────────────────────────
:EXPLORADOR
cls
color 1E
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [3] EXPLORADOR DE ARCHIVOS                                         ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  Volumenes disponibles:
echo  ────────────────────────────────────────────────────────────────────────
echo list volume | diskpart
echo.
echo  ────────────────────────────────────────────────────────────────────────
set /p EXPLVOL="  Letra del volumen a explorar (ej: C): "
set /p EXPLPATH="  Ruta a listar (ENTER para raiz): "
if "!EXPLPATH!"=="" set EXPLPATH=\
echo.
echo  Contenido de !EXPLVOL!:!EXPLPATH!
echo  ────────────────────────────────────────────────────────────────────────
dir "!EXPLVOL!:!EXPLPATH!" /a 2>nul
if errorlevel 1 (
    echo  [!] No se pudo acceder a !EXPLVOL!:!EXPLPATH!
    echo      El volumen puede estar bloqueado o la ruta no existe.
)
echo.
echo  [R] Explorar otra ruta   [M] Menu principal
set /p EXPROP="  Opcion: "
if /i "!EXPROP!"=="R" goto :EXPLORADOR
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [4] COPIAR ARCHIVOS / CARPETAS
:: ─────────────────────────────────────────────────────────────────────────────
:COPIAR_ARCHIVOS
cls
color 1A
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [4] COPIAR ARCHIVOS / CARPETAS (MEJORADO)                          ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  Unidades detectadas en el sistema:
echo  ────────────────────────────────────────────────────────────────────────
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%D:\ (
        for /f "usebackq tokens=*" %%A in (`fsutil fsinfo drivetype %%D: 2^>nul`) do (
            echo    [%%D:] - %%A
        )
    )
)
echo  ────────────────────────────────────────────────────────────────────────
echo.
set /p COPY_SRC_VOL="  Letra del volumen de ORIGEN (ej: C): "
if "!COPY_SRC_VOL!"=="" goto :MAIN_MENU

:: Quitar dos puntos por si el usuario los escribe (ej: C: -> C)
set COPY_SRC_VOL=!COPY_SRC_VOL::=!

if not exist "!COPY_SRC_VOL!:\" (
    echo [X] La unidad !COPY_SRC_VOL!: no existe o no es accesible.
    pause
    goto :COPIAR_ARCHIVOS
)

:: Escanear perfiles de usuario si es la unidad del sistema
set HAS_USERS=0
if exist "!COPY_SRC_VOL!:\Users" (
    set HAS_USERS=1
    echo.
    echo  Perfiles de usuario detectados en !COPY_SRC_VOL!:\Users\:
    echo  ────────────────────────────────────────────────────────────────────────
    set /a ucount=0
    for /d %%U in ("!COPY_SRC_VOL!:\Users\*") do (
        set "uname=%%~nxU"
        if /i not "!uname!"=="Public" if /i not "!uname!"=="Default" if /i not "!uname!"=="Default User" if /i not "!uname!"=="All Users" (
            set /a ucount+=1
            set "user_!ucount!=%%~nxU"
            echo    [!ucount!] %%~nxU
        )
    )
    echo    [0] Ruta personalizada [escribir ruta completa manualmente]
    echo  ────────────────────────────────────────────────────────────────────────
)

if "!HAS_USERS!"=="1" (
    set /p U_SEL="  Selecciona el usuario [1-!ucount! o 0]: "
    if "!U_SEL!"=="0" (
        set /p COPY_SRC_PATH="  Ruta de origen [ej: \Windows\System32]: "
    ) else (
        rem Validar seleccion
        set "SEL_USER="
        for /l %%I in (1,1,!ucount!) do (
            if "!U_SEL!"=="%%I" set "SEL_USER=!user_%%I!"
        )
        if "!SEL_USER!"=="" (
            echo [!] Seleccion invalida.
            pause
            goto :COPIAR_ARCHIVOS
        )
        
        echo.
        echo  ¿Que deseas copiar de !SEL_USER!?
        echo  ────────────────────────────────────────────────────────────────────────
        echo    [1] Todo el perfil completo [\Users\!SEL_USER!]
        echo    [2] Escritorio [\Users\!SEL_USER!\Desktop]
        echo    [3] Documentos [\Users\!SEL_USER!\Documents]
        echo    [4] Descargas [\Users\!SEL_USER!\Downloads]
        echo    [5] Imagenes [\Users\!SEL_USER!\Pictures]
        echo    [6] Datos de Chrome/Edge [\Users\!SEL_USER!\AppData\Local]
        echo    [7] Carpeta personalizada dentro del perfil
        echo  ────────────────────────────────────────────────────────────────────────
        set /p F_SEL="  Seleccion [1-7]: "
        
        if "!F_SEL!"=="1" set COPY_SRC_PATH=\Users\!SEL_USER!
        if "!F_SEL!"=="2" set COPY_SRC_PATH=\Users\!SEL_USER!\Desktop
        if "!F_SEL!"=="3" set COPY_SRC_PATH=\Users\!SEL_USER!\Documents
        if "!F_SEL!"=="4" set COPY_SRC_PATH=\Users\!SEL_USER!\Downloads
        if "!F_SEL!"=="5" set COPY_SRC_PATH=\Users\!SEL_USER!\Pictures
        if "!F_SEL!"=="6" set COPY_SRC_PATH=\Users\!SEL_USER!\AppData\Local
        if "!F_SEL!"=="7" (
            set /p SUBDIR="  Escribe la subcarpeta [ej: Documents\Proyectos]: "
            set COPY_SRC_PATH=\Users\!SEL_USER!\!SUBDIR!
        )
    )
) else (
    set /p COPY_SRC_PATH="  Ruta de origen [ej: \Datos]: "
)

echo.
echo  Ruta de origen configurada: !COPY_SRC_VOL!:!COPY_SRC_PATH!
echo.
echo  ────────────────────────────────────────────────────────────────────────
set /p COPY_DST_VOL="  Letra del volumen de DESTINO (ej: E): "
set COPY_DST_VOL=!COPY_DST_VOL::=!

if not exist "!COPY_DST_VOL!:\" (
    echo [X] La unidad !COPY_DST_VOL!: no existe o no es accesible.
    pause
    goto :COPIAR_ARCHIVOS
)

:: Definir sugerencia de carpeta destino
set "DEFAULT_DST_PATH=\Backup_!COPY_SRC_VOL!_Copia"
if "!HAS_USERS!"=="1" if not "!SEL_USER!"=="" (
    set "DEFAULT_DST_PATH=\Backup_!COPY_SRC_VOL!_!SEL_USER!"
)
:: Limpiar espacios o caracteres raros
set "DEFAULT_DST_PATH=!DEFAULT_DST_PATH: =_!"

echo.
set /p COPY_DST_PATH="  Carpeta destino [ENTER para !DEFAULT_DST_PATH!]: "
if "!COPY_DST_PATH!"=="" set COPY_DST_PATH=!DEFAULT_DST_PATH!

:: Asegurar que empieza con diagonal
if not "!COPY_DST_PATH:~0,1!"=="\" set "COPY_DST_PATH=\!COPY_DST_PATH!"

:: Crear carpeta destino
if not exist "!COPY_DST_VOL!:!COPY_DST_PATH!" (
    mkdir "!COPY_DST_VOL!:!COPY_DST_PATH!" >nul 2>&1
)

echo.
echo  Opciones de Robocopy:
echo  ────────────────────────────────────────────────────────────────────────
echo    [1] Copiar todo [con subcarpetas y archivos vacios]
echo    [2] Copiar solo archivos del nivel actual [sin subcarpetas]
echo    [3] Copiar con verificacion y reintento lento [mas seguro]
echo  ────────────────────────────────────────────────────────────────────────
set /p COPY_MODE="  Modo de copia [1-3]: "

echo.
echo  Copiando: !COPY_SRC_VOL!:!COPY_SRC_PATH! -> !COPY_DST_VOL!:!COPY_DST_PATH!
echo  Mostrando progreso en pantalla y guardando registro...
echo  ────────────────────────────────────────────────────────────────────────

:: Opciones de robocopy
set LOG_FILE="!COPY_DST_VOL!:!COPY_DST_PATH!\copy_log.txt"

if "!COPY_MODE!"=="1" (
    robocopy "!COPY_SRC_VOL!:!COPY_SRC_PATH!" "!COPY_DST_VOL!:!COPY_DST_PATH!" /E /COPYALL /R:1 /W:1 /TEE /LOG+:!LOG_FILE!
)
if "!COPY_MODE!"=="2" (
    robocopy "!COPY_SRC_VOL!:!COPY_SRC_PATH!" "!COPY_DST_VOL!:!COPY_DST_PATH!" /COPYALL /R:1 /W:1 /TEE /LOG+:!LOG_FILE!
)
if "!COPY_MODE!"=="3" (
    robocopy "!COPY_SRC_VOL!:!COPY_SRC_PATH!" "!COPY_DST_VOL!:!COPY_DST_PATH!" /E /COPYALL /R:3 /W:5 /TEE /LOG+:!LOG_FILE!
)

echo.
echo  [+] Copia completada. Registro guardado en: !COPY_DST_VOL!:!COPY_DST_PATH!\copy_log.txt
echo.
echo  [C] Copiar otra ruta   [M] Menu principal
set /p COPYOP="  Opcion: "
if /i "!COPYOP!"=="C" goto :COPIAR_ARCHIVOS
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [5] COPIA DE SEGURIDAD RAPIDA (PERFILES DE USUARIO)
:: ─────────────────────────────────────────────────────────────────────────────
:BACKUP_RAPIDO
cls
color 1A
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [5] COPIA RAPIDA - PERFILES DE USUARIO                            ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  Esta opcion copia los datos mas importantes de los perfiles de usuario.
echo.
:: Mostrar usuarios disponibles
if "!WIN_VOL!"=="" (
    set /p WIN_VOL="  Letra del volumen Windows (ej: C): "
)
echo  Perfiles encontrados en !WIN_VOL!:\Users\:
echo  ────────────────────────────────────────────────────────────────────────
dir "!WIN_VOL!:\Users\" /ad /b 2>nul
echo  ────────────────────────────────────────────────────────────────────────
echo.
set /p BK_USER="  Usuario a copiar (ENTER para TODOS): "
set /p BK_DST_VOL="  Letra disco destino (ej: E): "
set /p BK_DST_FOLDER="  Carpeta base en destino (ej: \Forensic_Backup): "
echo.
echo  Que deseas copiar:
echo    [1] Todo el perfil completo
echo    [2] Solo Documentos, Escritorio, Descargas, Imagenes
echo    [3] Solo Documentos y Escritorio
echo    [4] Archivos de credenciales y configuracion (AppData)
echo.
set /p BK_MODE="  Modo [1/2/3/4]: "
echo.

:: Crear carpeta base
if not exist "!BK_DST_VOL!:!BK_DST_FOLDER!" mkdir "!BK_DST_VOL!:!BK_DST_FOLDER!" >nul 2>&1

set ROBOCOPY_FLAGS=/E /COPYALL /R:1 /W:1 /NP /XJ

if "!BK_USER!"=="" (
    :: Todos los usuarios
    for /d %%U in ("!WIN_VOL!:\Users\*") do (
        set UNAME=%%~nxU
        if /i not "!UNAME!"=="Public" if /i not "!UNAME!"=="Default" if /i not "!UNAME!"=="Default User" (
            echo  [*] Copiando perfil: !UNAME!
            call :DO_USER_BACKUP "!WIN_VOL!" "!UNAME!" "!BK_DST_VOL!" "!BK_DST_FOLDER!" "!BK_MODE!"
        )
    )
) else (
    echo  [*] Copiando perfil: !BK_USER!
    call :DO_USER_BACKUP "!WIN_VOL!" "!BK_USER!" "!BK_DST_VOL!" "!BK_DST_FOLDER!" "!BK_MODE!"
)

echo.
echo  [+] Proceso de copia finalizado.
echo  Destino: !BK_DST_VOL!:!BK_DST_FOLDER!
echo.
pause
goto :MAIN_MENU

:DO_USER_BACKUP
:: Parametros: %1=VolOrigen %2=Usuario %3=VolDestino %4=FolderBase %5=Modo
set _SRC=%~1:\Users\%~2
set _DST=%~3:%~4\%~2
set _MODE=%~5
if not exist "!_DST!" mkdir "!_DST!" >nul 2>&1
if "!_MODE!"=="1" (
    robocopy "!_SRC!" "!_DST!" !ROBOCOPY_FLAGS! /LOG+:"%~3:%~4\backup_log.txt" >nul
)
if "!_MODE!"=="2" (
    for %%F in (Documents Desktop Downloads Pictures Videos Music) do (
        if exist "!_SRC!\%%F" (
            robocopy "!_SRC!\%%F" "!_DST!\%%F" !ROBOCOPY_FLAGS! /LOG+:"%~3:%~4\backup_log.txt" >nul
            echo      [+] %%F copiado
        )
    )
)
if "!_MODE!"=="3" (
    for %%F in (Documents Desktop) do (
        if exist "!_SRC!\%%F" (
            robocopy "!_SRC!\%%F" "!_DST!\%%F" !ROBOCOPY_FLAGS! /LOG+:"%~3:%~4\backup_log.txt" >nul
            echo      [+] %%F copiado
        )
    )
)
if "!_MODE!"=="4" (
    if exist "!_SRC!\AppData" (
        robocopy "!_SRC!\AppData\Roaming" "!_DST!\AppData\Roaming" !ROBOCOPY_FLAGS! /LOG+:"%~3:%~4\backup_log.txt" >nul
        echo      [+] AppData\Roaming copiado
    )
)
goto :EOF

:: ─────────────────────────────────────────────────────────────────────────────
:: [6] COPIAR ARCHIVOS POR TIPO
:: ─────────────────────────────────────────────────────────────────────────────
:COPIAR_POR_TIPO
cls
color 1D
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [6] COPIAR ARCHIVOS POR TIPO                                       ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  Tipos predefinidos:
echo    [1] Documentos     (*.pdf *.doc *.docx *.xls *.xlsx *.ppt *.txt)
echo    [2] Imagenes       (*.jpg *.jpeg *.png *.gif *.bmp *.raw *.heic)
echo    [3] Credenciales   (*.kdbx *.key *.pfx *.p12 *.pem *.ppk *.wallet)
echo    [4] Codigo fuente  (*.py *.js *.php *.cs *.cpp *.java *.sql)
echo    [5] Bases de datos (*.db *.sqlite *.mdb *.accdb *.bak)
echo    [6] Tipo personalizado
echo.
set /p TIPO_OP="  Tipo [1-6]: "
echo.

if "!TIPO_OP!"=="1" set FILTROS=*.pdf *.doc *.docx *.xls *.xlsx *.pptx *.txt *.csv *.odt
if "!TIPO_OP!"=="2" set FILTROS=*.jpg *.jpeg *.png *.gif *.bmp *.raw *.heic *.tiff *.cr2
if "!TIPO_OP!"=="3" set FILTROS=*.kdbx *.key *.pfx *.p12 *.pem *.ppk *.wallet *.keystore *.dat
if "!TIPO_OP!"=="4" set FILTROS=*.py *.js *.php *.cs *.cpp *.java *.sql *.ts *.go *.rb
if "!TIPO_OP!"=="5" set FILTROS=*.db *.sqlite *.sqlite3 *.mdb *.accdb *.bak *.sql
if "!TIPO_OP!"=="6" (
    set /p FILTROS="  Extensiones (ej: *.pdf *.doc): "
)

set /p TIPO_SRC_VOL="  Volumen origen (ej: C): "
set /p TIPO_SRC_PATH="  Carpeta origen (ej: \Users\ para buscar en todos los perfiles): "
set /p TIPO_DST_VOL="  Volumen destino (ej: E): "
set /p TIPO_DST_PATH="  Carpeta destino (ej: \Docs_Copiados): "

if not exist "!TIPO_DST_VOL!:!TIPO_DST_PATH!" mkdir "!TIPO_DST_VOL!:!TIPO_DST_PATH!" >nul 2>&1

echo.
echo  Copiando archivos tipo [!FILTROS!]
echo  De: !TIPO_SRC_VOL!:!TIPO_SRC_PATH!  →  A: !TIPO_DST_VOL!:!TIPO_DST_PATH!
echo  ────────────────────────────────────────────────────────────────────────
robocopy "!TIPO_SRC_VOL!:!TIPO_SRC_PATH!" "!TIPO_DST_VOL!:!TIPO_DST_PATH!" !FILTROS! ^
    /S /COPYALL /R:1 /W:1 /NP /LOG+:"!TIPO_DST_VOL!:!TIPO_DST_PATH!\copy_log.txt"

echo.
echo  [+] Copia por tipo completada.
echo.
echo  [V] Copiar otro tipo   [M] Menu principal
set /p TIPOOP="  Opcion: "
if /i "!TIPOOP!"=="V" goto :COPIAR_POR_TIPO
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [7] INFORMACION DEL SISTEMA Y TPM
:: ─────────────────────────────────────────────────────────────────────────────
:INFO_SISTEMA
cls
color 1B
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [7] INFORMACION DEL SISTEMA Y TPM                                  ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  ── Identificacion del equipo ────────────────────────────────────────────
echo  Nombre:  %COMPUTERNAME%
echo  Fecha:   %DATE%  %TIME%
wmic computersystem get Manufacturer,Model,Name /value 2>nul
echo.
echo  ── Chip TPM ──────────────────────────────────────────────────────────────
wmic /namespace:\\root\cimv2\security\microsofttpm path win32_tpm ^
    get IsActivated_InitialValue,IsEnabled_InitialValue,ManufacturerID,^
    ManufacturerVersion,SpecVersion /value 2>nul
echo.
echo  ── BIOS / UEFI ───────────────────────────────────────────────────────────
wmic bios get Manufacturer,Name,Version,SMBIOSBIOSVersion /value 2>nul
echo.
echo  ── Secure Boot ───────────────────────────────────────────────────────────
reg query HKLM\SYSTEM\CurrentControlSet\Control\SecureBootStatus /v Enabled 2>nul
echo.
pause
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [8] GUARDAR REPORTE COMPLETO
:: ─────────────────────────────────────────────────────────────────────────────
:GUARDAR_REPORTE
cls
color 1B
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [8] GUARDAR REPORTE COMPLETO                                       ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
set /p RPT_VOL="  Letra disco destino para reporte (ej: E): "
set RPT_FILE=!RPT_VOL!:\BL_Report_%COMPUTERNAME%_%DATE:~-4,4%%DATE:~-7,2%%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%.txt
set RPT_FILE=!RPT_FILE: =0!
echo.
echo  Guardando reporte en: !RPT_FILE!
echo  ────────────────────────────────────────────────────────────────────────
(
    echo ============================================================
    echo  REPORTE FORENSE BITLOCKER - JernelSystems Research
    echo ============================================================
    echo  Equipo   : %COMPUTERNAME%
    echo  Fecha    : %DATE% %TIME%
    echo.
    echo === [1] ESTADO BITLOCKER ===
    !BDE_CMD! -status
    echo.
    echo === [2] PROTECTORES POR VOLUMEN ===
    for %%D in (C D E F G H I) do (
        echo --- Volumen %%D: ---
        !BDE_CMD! -protectors -get %%D: 2>nul
    )
    echo.
    echo === [3] INFORMACION TPM ===
    wmic /namespace:\\root\cimv2\security\microsofttpm path win32_tpm get * /value 2>nul
    echo.
    echo === [4] VOLUMENES ===
    echo list volume | diskpart
    echo.
    echo === [5] INFORMACION BIOS ===
    wmic bios get Manufacturer,Name,SMBIOSBIOSVersion /value 2>nul
    echo.
    echo === [6] ARCHIVOS EFI ===
    mountvol S: /s >nul 2>&1
    dir S:\EFI\ /s 2>nul
    echo.
    echo === [7] VARIABLES DE ENTORNO ===
    set
    echo.
    echo ============================================================
    echo  FIN DEL REPORTE
    echo ============================================================
) > "!RPT_FILE!" 2>&1

if exist "!RPT_FILE!" (
    echo  [+] Reporte guardado exitosamente.
    for %%F in ("!RPT_FILE!") do echo  Tamano: %%~zF bytes
) else (
    echo  [!] Error al guardar el reporte. Verifica que el disco este conectado.
)
echo.
pause
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [9] CMD INTERACTIVO AVANZADO
:: ─────────────────────────────────────────────────────────────────────────────
:CMD_AVANZADO
cls
color 07
echo.
echo  ╔══════════════════════════════════════════════════════════════════════╗
echo  ║   [9] SHELL INTERACTIVO - BitUnlocker WinRE                          ║
echo  ╚══════════════════════════════════════════════════════════════════════╝
echo.
echo  Comandos utiles:
echo    manage-bde -status C:           ^> Estado BitLocker
echo    manage-bde -protectors -get C:  ^> Ver claves/protectores
echo    diskpart                         ^> Gestionar volumenes
echo    robocopy C:\Users E:\Backup /E  ^> Copiar carpeta completa
echo    dir C:\Users\ /ad               ^> Listar perfiles de usuario
echo    xcopy C:\ruta E:\destino /E /H  ^> Copia alternativa
echo    exit                             ^> Volver al menu
echo.
echo  ────────────────────────────────────────────────────────────────────────
echo  Escribe 'exit' para volver al menu principal.
echo.
cmd.exe /k "prompt [BitUnlocker] $P$G & echo. & echo Escribe exit para volver al menu."
goto :MAIN_MENU

:: ─────────────────────────────────────────────────────────────────────────────
:: [0] SALIR
:: ─────────────────────────────────────────────────────────────────────────────
:SALIR
cls
echo.
echo  Cerrando BitLocker Forensic Toolkit...
echo  JernelSystems Research - Solo uso en equipos propios o con permiso escrito.
echo.
endlocal
exit /b 0
