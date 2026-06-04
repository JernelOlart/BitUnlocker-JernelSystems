# Scripts — BitUnlocker Research Toolkit

Scripts para construir un WinRE personalizado con menú forense interactivo.
**Uso exclusivo en equipos propios o con permiso escrito.**

---

## Archivos

| Script | Plataforma | Descripción |
|--------|-----------|-------------|
| `get_files_from_iso.ps1` | Windows (Admin) | **PASO 1** — Extrae `WinRE.wim` y `boot.sdi` desde una ISO de Windows 11 |
| `build_custom_winre.ps1` | Windows (Admin) | **PASO 2** — Monta el WIM, inyecta el menú forense y genera el SDI final |
| `bitlocker_diag.cmd`     | WinRE (target)  | Menú interactivo que corre dentro del WinRE parcheado al arrancar |
| `patch_sdi.py`           | Python 3        | Parchea un `boot.sdi` con un WIM personalizado |
| `parse_sdi.py`           | Python 3        | Valida y muestra la estructura de un archivo SDI |

---

## Flujo completo

```
ISO Windows 11
      │
      ▼
[1] get_files_from_iso.ps1
      │  → custom_winre_base.wim
      │  → boot.sdi
      │
      ▼
[2] build_custom_winre.ps1
      │  Monta WIM → inyecta bitlocker_diag.cmd → guarda WIM
      │  → Llama a patch_sdi.py internamente
      │  → boot_patched_custom.sdi
      │
      ▼
Copiar a USB/sdi/boot_patched.sdi
      │
      ▼
Arrancar en laptop objetivo
      │
      ▼
[MENU INTERACTIVO] bitlocker_diag.cmd
```

---

## PASO 1 — Extraer archivos de la ISO

```powershell
# En PowerShell como Administrador
.\get_files_from_iso.ps1 -IsoPath "C:\Win11_23H2.iso"

# Con directorio de salida personalizado
.\get_files_from_iso.ps1 -IsoPath "C:\Win11.iso" -OutputDir "C:\BitUnlocker_Files"
```

**Resultado:**
- `custom_winre_base.wim` — WinRE base para modificar
- `boot.sdi` — SDI stock necesario para patch_sdi.py

> Si no tienes ISO: [Descargar Windows 11 ISO oficial](https://www.microsoft.com/es-es/software-download/windows11)

---

## PASO 2 — Construir WinRE con menú forense

```powershell
# Básico (genera solo el WIM)
.\build_custom_winre.ps1 -WimPath ".\custom_winre_base.wim"

# Completo (genera WIM + SDI final listo para usar)
.\build_custom_winre.ps1 `
  -WimPath   ".\custom_winre_base.wim" `
  -StockSdi  ".\boot.sdi" `
  -OutputWim ".\custom_winre.wim"

# Con herramientas extra (ej: sigcheck.exe de Sysinternals)
.\build_custom_winre.ps1 `
  -WimPath        ".\custom_winre_base.wim" `
  -StockSdi       ".\boot.sdi" `
  -ExtraToolsDir  "C:\Sysinternals"
```

**Resultado:** `boot_patched_custom.sdi` — listo para copiar a `USB\sdi\boot_patched.sdi`

---

## Menú interactivo (dentro del WinRE)

Al arrancar el WinRE parcheado aparece automáticamente:

```
╔══════════════════════════════════════════════════════════════════════╗
║       BITLOCKER FORENSIC TOOLKIT  |  JernelSystems Research        ║
╠══════════════════════════════════════════════════════════════════════╣
║   [1]  Diagnostico completo BitLocker                               ║
║   [2]  Ver protectores y claves de cifrado                          ║
║   [3]  Explorador de archivos interactivo                           ║
║   [4]  Copiar archivos / carpetas                                   ║
║   [5]  Copia de seguridad rapida (perfiles de usuario)              ║
║   [6]  Copiar archivos especificos por tipo                         ║
║   [7]  Informacion del sistema y TPM                                ║
║   [8]  Guardar reporte completo                                     ║
║   [9]  Abrir CMD interactivo avanzado                               ║
║   [0]  Salir                                                        ║
╚══════════════════════════════════════════════════════════════════════╝
```

### Opción 4 — Copiar archivos/carpetas
Copia cualquier ruta origen → destino usando `robocopy` con 3 modos:
- Carpeta completa con subcarpetas
- Solo nivel actual
- Con verificación (más seguro)

### Opción 5 — Backup rápido de perfiles
Detecta automáticamente los perfiles de usuario y permite copiar:
- Todo el perfil completo
- Solo Documentos, Escritorio, Descargas, Imágenes
- Solo Documentos y Escritorio
- Datos de AppData/credenciales

### Opción 6 — Copiar por tipo de archivo
Filtros predefinidos:
| Tipo | Extensiones |
|------|-------------|
| Documentos | pdf, doc, docx, xls, xlsx, pptx, txt, csv |
| Imágenes | jpg, png, gif, raw, heic, tiff |
| Credenciales | kdbx, key, pfx, pem, ppk, wallet |
| Código fuente | py, js, php, cs, cpp, java, sql |
| Bases de datos | db, sqlite, mdb, accdb, bak |
| Personalizado | cualquier extensión |

---

## Herramientas recomendadas para ExtraToolsDir

Coloca estos ejecutables en una carpeta y pásala con `-ExtraToolsDir`:

| Herramienta | Descarga | Uso dentro del WinRE |
|-------------|----------|---------------------|
| `sigcheck.exe` | [Sysinternals](https://learn.microsoft.com/en-us/sysinternals/downloads/sigcheck) | Verificar certificado de bootmgfw.efi |
| `autoruns.exe` | [Sysinternals](https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns) | Ver arranque automático |
| `diskpart.exe` | Built-in WinPE | Gestionar volúmenes |

---

## Solución de problemas

| Error | Solución |
|-------|----------|
| DISM falla al montar | Ejecutar como Administrador; verificar que el WIM no esté corrupto |
| `boot.sdi` no encontrado en ISO | Buscar en `C:\Windows\Boot\DVD\EFI\en-US\boot.sdi` |
| `WinRE.wim` no en boot.wim | El script usará automáticamente el WinRE del sistema actual |
| USB no aparece en menú boot | Usar "Boot from file" → `EFI/Boot/bootx64.efi` en el UEFI |
| Pantalla azul al arrancar | El equipo ya migró a CA 2023 — no vulnerable ✅ |
