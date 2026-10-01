# CCDC Red Team Training Artifacts

Repositorio de escenarios deliberadamente vulnerables, checkers de limpieza y
herramientas de observación para prácticas autorizadas de CCDC. Los nombres
`redhavi*` se conservan en los scripts históricos para no romper despliegues y
material de clase; el monitor web se llama `ccdc-canary-monitor`.

Versión navegable por secciones: [ccdc_php.html](ccdc-php/ccdc_php.html).

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
| `windows-dos-combined/redhaviwin.ps1` | Windows | Prepara el escenario Windows con cuentas, persistencia, web y check-ins. | Sí |
| `windows-dos-combined/redhavi-checkWin.ps1` | Windows | Proporciona los 11 controles Redhavi usados por el checker combinado. | No |
| `redhavi-checkWin-ps2exe.ps1` | Windows | Empaqueta el checker de PowerShell como EXE mediante PS2EXE. | Crea un archivo |
| `windows-dos-combined/dos.ps1` | Windows | Prepara el escenario completo y añade `ccdcscoring.exe` con su tarea programada. | Sí |
| `windows-dos-combined/dos-checkWin.ps1` | Windows | Evalúa los 11 controles Redhavi y los 2 artefactos adicionales de `dos.ps1`. | No |
| `windows-dos-combined/dos-checkWin-ps2exe.ps1` | Windows | Empaqueta el checker combinado como un EXE autocontenido mediante PS2EXE. | Crea un archivo |
| `ccdc-canary-monitor` | Python 3 | Servidor de check-ins y dashboard web para el instructor. | Solo su JSON de estado |
| `ecomredhavi` | Ubuntu/Debian | Laboratorio Apache, PHP y MySQL con configuraciones débiles e indicadores inertes. | Sí |
| `ecomredhavimysql` | Ubuntu/Debian | Variante explícita del laboratorio web/MySQL con headers débiles y contraseñas conocidas. | Sí |
| `instservices` | Ubuntu Server 24.04 | Instala Postfix, Dovecot, 12 usuarios de correo, Apache y PHP con fallos intencionales. | Sí |
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

El escenario combinado está en `windows-dos-combined/`. Ejecuta PowerShell 5.1
de 64 bits como Administrador:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
Set-Location .\windows-dos-combined
.\dos.ps1
.\dos-checkWin.ps1
```

Para crear y ejecutar el checker autocontenido:

```powershell
.\dos-checkWin-ps2exe.ps1 -Force
.\Dos_team_artifacts.exe
```

Consulta [las instrucciones completas del escenario combinado](windows-dos-combined/README.md).

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

También crea 12 usuarios locales legítimos: `ana.garcia`, `carlos.lopez`,
`maria.rodriguez`, `jose.martinez`, `laura.hernandez`, `pedro.sanchez`,
`sofia.ramirez`, `diego.torres`, `elena.flores`, `miguel.rivera`, `lucia.gomez`
y `andres.diaz`. Cada cuenta nueva recibe una contraseña generada durante la
instalación y un buzón `~/Maildir` con las carpetas `cur`, `new` y `tmp`.
Las contraseñas iniciales se guardan en `/root/instservices-mail-users.tsv`
en el servidor; consulta el archivo con:

```bash
sudo cat /root/instservices-mail-users.tsv
```

Para leer correo, conecta un cliente IMAP al servidor en el puerto `143`,
usando el nombre de usuario sin dominio (por ejemplo, `ana.garcia`) y su
contraseña. La dirección de correo es `usuario@DOMINIO`, con el dominio
seleccionado mediante `--mail-domain`. Dovecot ya forma parte de la instalación.
Al repetir el instalador, se conservan las cuentas, contraseñas y mensajes
existentes. El archivo registra solo las contraseñas iniciales de las cuentas
creadas por el instalador.
Los permisos y las vulnerabilidades intencionales del laboratorio se mantienen.

### Leer correo desde CLI

Ejecuta los comandos de lectura desde el servidor o desde otro equipo de la
red del laboratorio. En Ubuntu, instala el cliente si hace falta:

```bash
sudo apt-get install -y curl
```

Define la variable `$ipphpserver` con la IP de la VM en la misma terminal donde
ejecutarás las pruebas, así puedes copiar los comandos tal cual. Si estás en el
propio servidor, usa `127.0.0.1`:

```bash
export ipphpserver="192.168.1.100"  # Reemplaza con la IP real del servidor de correo
```

Usa una de las 12 cuentas, por ejemplo `ana.garcia`, y consulta su contraseña
inicial en `/root/instservices-mail-users.tsv` en el servidor. Al indicar solo
el usuario con `--user`, curl solicita la contraseña en la terminal.
Estos ejemplos usan IMAP/143 sin TLS, tal como permite el laboratorio.

**1. Listar los buzones disponibles:**

```bash
curl --silent --show-error --user ana.garcia \
  --url "imap://$ipphpserver:143/"
```

**2. Buscar los identificadores (UID) de los mensajes en INBOX:**

```bash
curl --silent --show-error --user ana.garcia \
  --url "imap://$ipphpserver:143/INBOX" \
  --request 'UID SEARCH ALL'
```

Una respuesta como `* SEARCH 1 2` indica que existen los UID `1` y `2`.
Si devuelve `* SEARCH` sin números, el buzón está vacío.

**3. Leer un mensaje completo, incluidos encabezados y cuerpo:**

```bash
curl --silent --show-error --user ana.garcia \
  --url "imap://$ipphpserver:143/INBOX/;UID=1"
```

Sustituye `1` por uno de los UID que devolvió la búsqueda; los UID no tienen
por qué ser consecutivos. Mantén las comillas dobles de la URL: protegen el `;` y permiten que `$ipphpserver` se sustituya.
La [documentación de curl sobre IMAP](https://curl.se/docs/url-syntax.html#imap)
describe estas búsquedas y la lectura por UID.

**4. Enviar un correo de prueba local para tener algo que leer:**

Ejecuta esto en el servidor de correo. Si usaste otro `--mail-domain`, cambia
`ccdcteam.com` en las dos direcciones:

```bash
printf '%s\n' \
  'From: carlos.lopez@ccdcteam.com' \
  'To: ana.garcia@ccdcteam.com' \
  'Subject: Prueba de correo CCDC' \
  '' \
  'Hola Ana, este es un mensaje de prueba del laboratorio.' |
  sudo -u carlos.lopez /usr/sbin/sendmail -i -t
```

Después repite la búsqueda y lectura de INBOX. Postfix entrega el mensaje
al Maildir de Ana y Dovecot permite leerlo por IMAP.

**5. Enviar un correo con curl por SMTP (desde cualquier equipo del laboratorio):**

El paso 4 usa `sendmail` en el propio servidor. Desde otro equipo de la red
puedes enviar con curl al puerto 25 sin autenticación, porque el dominio local
está en `mydestination` de Postfix. Si usaste otro `--mail-domain`, cambia el
dominio en las dos direcciones:

```bash
printf '%s\r\n' \
  'From: carlos.lopez@ccdcteam.com' \
  'To: ana.garcia@ccdcteam.com' \
  'Subject: Prueba con curl' \
  '' \
  'Mensaje enviado con curl desde un equipo del laboratorio.' |
  curl --silent --show-error \
    --url "smtp://$ipphpserver:25" \
    --mail-from carlos.lopez@ccdcteam.com \
    --mail-rcpt ana.garcia@ccdcteam.com \
    --upload-file -
```

Después vuelve a ejecutar la búsqueda del paso 2 para ver el nuevo UID.

**6. Borrar un mensaje de prueba (limpieza del buzón):**

Marca el mensaje con la bandera `\Deleted` y luego ejecuta `EXPUNGE`. Sustituye
`2` por el UID que quieras eliminar:

```bash
curl --silent --show-error --user ana.garcia \
  --url "imap://$ipphpserver:143/INBOX" \
  --request 'UID STORE 2 +FLAGS.SILENT \Deleted'

curl --silent --show-error --user ana.garcia \
  --url "imap://$ipphpserver:143/INBOX" \
  --request 'EXPUNGE'
```

Vuelve a listar con `UID SEARCH ALL` para confirmar que el UID ya no aparece.

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
