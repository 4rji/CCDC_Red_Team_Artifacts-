# CCDC Red Team Training Artifacts

Repositorio de escenarios deliberadamente vulnerables, checkers de limpieza y
herramientas de observación para prácticas autorizadas de CCDC. Los nombres
`redhavi*` se conservan en los scripts históricos para no romper despliegues y
material de clase; el monitor web se llama `ccdc-canary-monitor`.

> [!CAUTION]
> Los seeders crean usuarios débiles, persistencia, claves SSH, contenido web
> vulnerable y servicios inseguros. Úsalos únicamente en máquinas virtuales
> desechables, aisladas y con snapshot. Nunca en producción ni directamente en
> Internet.

## Mapa rápido

| Archivo | Plataforma | Función | Modifica el sistema |
| --- | --- | --- | --- |
| `redhavi` | Ubuntu | Escenario Linux base: paquetes inseguros, usuarios, cron, webshell de práctica y clave SSH. | Sí |
| `redhavi-ubuntu24` | Ubuntu 24.04 | Perfil del escenario base que además instala el check-in periódico al monitor. | Sí |
| `redhavi-fedora` | Fedora | Escenario equivalente para Fedora; por defecto solo muestra un dry-run. | Solo con `--apply` |
| `redhavi-check` | Ubuntu/Linux | Evalúa la limpieza del escenario Linux base. | No |
| `redhavi-check-ubuntu24` | Ubuntu 24.04 | Evalúa 10 controles, incluido el servicio/timer canary. | No |
| `redhavi-check-fedora` | Fedora | Evalúa la limpieza del escenario Fedora. | No |
| `redhavi-check-shc` | Linux | Fuente adaptada para compilar el checker Linux con SHC. | No |
| `redhavi-check-federo-shc` | Fedora | Fuente SHC del checker Fedora; el nombre `federo` es histórico. | No |
| `redhaviwin.ps1` | Windows | Prepara el escenario Windows con cuentas, persistencia, web y check-ins. | Sí |
| `redhavi-checkWin.ps1` | Windows | Evalúa la limpieza del escenario Windows. | No |
| `redhavi-checkWin-ps2exe.ps1` | Windows | Empaqueta el checker de PowerShell como EXE mediante PS2EXE. | Crea un archivo |
| `ccdc-canary-monitor` | Python 3 | Servidor de check-ins y dashboard web para el instructor. | Solo su JSON de estado |
| `ecomredhavi` | Ubuntu/Debian | Laboratorio Apache, PHP y MySQL con configuraciones débiles e indicadores inertes. | Sí |
| `ecomredhavimysql` | Ubuntu/Debian | Variante explícita del laboratorio web/MySQL con headers débiles y contraseñas conocidas. | Sí |
| `instservices` | Ubuntu Server 24.04 | Instala Postfix, Dovecot, Apache y PHP con fallos intencionales. | Sí |
| `redhavi-apolloWin.ps1` | Windows | Artefacto opcional de tarea programada para un payload Apollo autorizado. | Sí |
| `redhavi-poseidon` | Linux/systemd | Artefacto opcional de servicio y timer para un payload Poseidon autorizado. | Sí |
| `redhavi-task.md` | Todas | Hoja de investigación que se entrega al Blue Team. | No |
| `INSTALLATION.md` | Todas | Guía detallada de instalación, compilación y solución de problemas. | No |

`apollo1.exe` y `poseidon.bin` son placeholders vacíos. No son payloads
funcionales.

## Flujo recomendado de una práctica

1. Crea una VM desechable compatible y toma un snapshot.
2. Aísla la red de producción e Internet.
3. Si el escenario usa canaries, inicia primero `ccdc-canary-monitor` en el
   equipo del instructor.
4. Ejecuta **un** seeder apropiado para el sistema operativo.
5. Guarda la salida inicial del checker correspondiente.
6. Entrega `redhavi-task.md` y el checker al equipo.
7. Repite el checker después de cada grupo de correcciones.
8. Comprueba que cesen los check-ins, sin asumir que verde demuestra limpieza.
9. Guarda resultados y restaura el snapshot.

No mezcles varios seeders en la misma VM salvo que el diseño del ejercicio lo
requiera expresamente.

## Monitor web de canaries

El monitor registra la IP, cantidad de check-ins y tiempo desde la última
conexión:

- **RED**: la máquina llamó recientemente a `/checkin`; la persistencia parece
  seguir activa.
- **GREEN**: superó el umbral sin llamar. También puede significar VM apagada,
  pérdida de red o bloqueo por firewall; no sustituye al checker.

No tiene autenticación. Ejecútalo solamente en la interfaz de la red aislada.

```bash
mkdir -p build
python3 ./ccdc-canary-monitor \
  --bind IP_DEL_MONITOR \
  --port 8081 \
  --clean-threshold 240 \
  --state ./build/ccdc-monitor-state.json
```

Abre `http://IP_DEL_MONITOR:8081/`. Prueba un check-in inocuo con:

```bash
curl --fail --silent --show-error http://IP_DEL_MONITOR:8081/checkin
curl --fail --silent --show-error http://IP_DEL_MONITOR:8081/api/status
```

Opciones principales:

| Opción | Valor predeterminado | Uso |
| --- | --- | --- |
| `--bind` | `0.0.0.0` | Interfaz donde escucha. Es mejor indicar la IP aislada. |
| `--port` | `8081` | Puerto HTTP. |
| `--clean-threshold` | `240` | Segundos sin check-in antes de mostrar verde. |
| `--state` | `~/.ccdc-canary-monitor.json` | JSON persistente del dashboard. |
| `--payload` | Canary inocuo incluido | Archivo que devuelve `/checkin`. |
| `--no-auto-discover` | Desactivado | Evita añadir automáticamente IPs nuevas. |

## Ubuntu base

El seeder `redhavi` instala el escenario Ubuntu histórico. No activa el timer
del monitor en su perfil predeterminado.

```bash
sudo ./redhavi
sudo ./redhavi --verify
sudo ./redhavi-check
```

El checker exige el marcador preparado en `/var/lib/redhavi/state`. Ejecutarlo
sin haber desplegado el escenario correspondiente produce un error de
infraestructura, no una puntuación válida.

## Ubuntu 24.04 con monitor

Este es el perfil recomendado cuando se quiere visualizar la persistencia en
el dashboard. `redhavi-ubuntu24` debe permanecer junto a `redhavi`, y
`redhavi-check-ubuntu24` junto a `redhavi-check`.

```bash
sudo CANARY_URL=http://IP_DEL_MONITOR:8081/checkin \
  ./redhavi-ubuntu24

sudo ./redhavi-ubuntu24 --verify
sudo ./redhavi-check-ubuntu24
```

El perfil exige exactamente Ubuntu 24.04. Instala
`redhavi-canary.service` y `redhavi-canary.timer`; el timer llama al monitor
cada tres minutos. Puedes cambiar el intervalo durante el sembrado:

```bash
sudo CANARY_URL=http://IP_DEL_MONITOR:8081/checkin \
  CANARY_INTERVAL=5 ./redhavi-ubuntu24
```

## Fedora

Sin argumentos, el seeder hace un dry-run seguro. Revisa primero esa salida:

```bash
./redhavi-fedora
```

Para aplicar el escenario en una VM Fedora autorizada:

```bash
sudo CANARY_URL=http://IP_DEL_MONITOR:8081/checkin \
  ./redhavi-fedora --apply
```

La confirmación interactiva requiere escribir `LAB`. Para automatizar una VM
ya aislada se puede añadir `--yes`:

```bash
sudo CANARY_URL=http://IP_DEL_MONITOR:8081/checkin \
  ./redhavi-fedora --apply --yes

sudo ./redhavi-check-fedora
```

## Windows

Ejecuta PowerShell 5.1 de 64 bits como Administrador. El seeder instala su
check-in canary cada tres minutos y acepta una URL específica:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\redhaviwin.ps1 -CanaryUrl 'http://IP_DEL_MONITOR:8081/checkin'
.\redhaviwin.ps1 -Verify
.\redhavi-checkWin.ps1
```

Para compilar el checker como EXE:

```powershell
.\redhavi-checkWin-ps2exe.ps1 -InstallPs2Exe
.\redhavi-checkWin.exe
```

Usa `-Force` en el compilador solamente cuando quieras reemplazar
intencionalmente un EXE existente.

## Laboratorios web, base de datos y servicios

### Apache, PHP y MySQL

Los dos scripts siguientes instalan paquetes y cambian la configuración real
de Apache/MySQL. No tienen modo dry-run ni checker dedicado.

```bash
./ecomredhavi
# o, para la variante con más ajustes débiles explícitos:
./ecomredhavimysql
```

Crean bases y usuarios `magento`, `opencart`, `wordpress` y `drupal`, con la
contraseña de práctica `metro`, un sitio adicional en el puerto `8080`,
`phpinfo`, listado de directorios e indicadores web inertes.

### Correo y web en Ubuntu Server 24.04

Consulta primero la ayuda y luego ejecuta con confirmación:

```bash
./instservices --help
sudo ./instservices \
  --mail-hostname mail.ccdcteam.com \
  --mail-domain ccdcteam.com
```

En automatización controlada se puede añadir `--yes`. Instala SMTP/25,
IMAP/143, HTTP/80 y HTTPS/443, además de permisos débiles, divulgación de
versiones, listado de directorios y una XSS reflejada de laboratorio.

## Artefactos opcionales Apollo y Poseidon

Estos scripts requieren un payload recién generado para un ejercicio
autorizado. Los placeholders incluidos no funcionan. Usa siempre un SHA-256
conocido y un servidor aislado.

Windows/Apollo:

```powershell
.\redhavi-apolloWin.ps1 `
  -DownloadUrl 'http://SERVIDOR_AUTORIZADO:8087/apollo1.exe' `
  -ExpectedSha256 'HASH_SHA256_DE_64_CARACTERES'

.\redhavi-apolloWin.ps1 -Remove
```

Linux/Poseidon:

```bash
sudo ./redhavi-poseidon \
  --download-url http://SERVIDOR_AUTORIZADO:8087/poseidon.bin \
  --expected-sha256 HASH_SHA256_DE_64_CARACTERES

sudo ./redhavi-poseidon --remove
```

Los checkers principales no puntúan estos artefactos opcionales.

## Interpretación de los checkers

| Código | Significado |
| --- | --- |
| `0` | Todos los controles puntuados pasaron. |
| `1` | Quedan hallazgos del escenario. |
| `2` | Error de infraestructura, permisos, estado o dependencia, cuando el checker distingue esta condición. |

Un checker solo evalúa su rúbrica. Un resultado limpio no demuestra por sí
solo que la máquina esté libre de toda actividad maliciosa.

## Validación antes de desplegar

Desde la raíz del repositorio:

```bash
bash -n redhavi redhavi-ubuntu24 redhavi-fedora \
  redhavi-check redhavi-check-ubuntu24 redhavi-check-fedora \
  redhavi-check-shc redhavi-check-federo-shc redhavi-poseidon \
  ecomredhavi ecomredhavimysql instservices

python3 -m py_compile ccdc-canary-monitor
```

Si está instalado:

```bash
shellcheck redhavi redhavi-* ecomredhavi* instservices
```

Consulta [INSTALLATION.md](INSTALLATION.md) para compilación con SHC, copia a
otras VMs, empaquetado de Windows y resolución de problemas.

## Seguridad y recuperación

- Guarda snapshots antes de sembrar un escenario.
- No confirmes cambios si el sistema operativo o la red no son los esperados.
- No subas credenciales, claves privadas, payloads reales ni archivos de
  estado al repositorio.
- Limita el puerto `8081` del monitor a la red de práctica.
- Verifica hashes de todo artefacto descargado.
- Restaura la VM al terminar; no confíes únicamente en una limpieza manual.

Este es un proyecto educativo independiente; no está afiliado oficialmente a
CCDC.
