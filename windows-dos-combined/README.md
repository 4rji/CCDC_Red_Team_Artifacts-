# Escenario combinado Redhavi + DOS para Windows

Esta carpeta contiene todo lo necesario para preparar y evaluar el escenario de 13 controles:

- 11 controles originales de Redhavi.
- La tarea programada `Redhavi-ccdcscoring`.
- El ejecutable `C:\ProgramData\CCDC-Lab\ccdcscoring.exe`.

## Instrucciones

Usa una máquina virtual desechable. Abre Windows PowerShell 5.1 como Administrador y entra en esta carpeta.

### 1. Preparar el escenario

```powershell
.\dos.ps1
```

Si Redhavi llega a `post-validation` con alguna comprobación pendiente, el escenario combinado permite continuar y el checker mostrará el estado real de cada control.

### 2. Ejecutar el checker en PowerShell

```powershell
.\dos-checkWin.ps1
```

Con todos los artefactos instalados, el resultado inicial esperado es `0%`.

### 3. Crear el checker ejecutable

```powershell
.\dos-checkWin-ps2exe.ps1 -Force
```

Este comando crea `Dos_team_artifacts.exe` e incorpora el checker Redhavi dentro del ejecutable.

### 4. Ejecutar el checker compilado

```powershell
.\Dos_team_artifacts.exe
```

Conserva estos dos marcadores durante el ejercicio:

```text
C:\ProgramData\redhavi\state-win.json
C:\ProgramData\redhavi\dos-state-win.json
```

## Resultado inicial validado

```text
=== Combined Redhavi + DOS Windows Cleanup Verification ===
Redhavi state: C:\ProgramData\redhavi\state-win.json
DOS state:      C:\ProgramData\redhavi\dos-state-win.json
WARNING: Redhavi reached post-validation with one or more seed checks unresolved.

[X]     [user_ccdc           ] the account is still enabled
[X]     [user_splunk         ] the account is still enabled
[X]     [scheduled_task      ] persistence was found in: task:\Redhavi-IndexRefresh, file:C:\ProgramData\redhavi\redhavi-index-refresh.ps1
[X]     [registry_run        ] registry persistence was found in HKLM:\Software\Microsoft\Windows\CurrentVersion\Run: RedhaviIndexRefresh
[X]     [canary_task         ] periodic canary artifacts were found: task:\Redhavi-CanaryCheckin, file:C:\ProgramData\redhavi\redhavi-registry-canary.ps1
[X]     [ssh_lab_key         ] the exact lab SSH key is still present
[X]     [ssh_readonly        ] C:\ProgramData\ssh\administrators_authorized_keys still has the ReadOnly attribute
[X]     [webshell            ] shell_exec is still present in C:\xampp\htdocs\simple-php-website\index.php
[X]     [web_readonly        ] C:\xampp\htdocs\simple-php-website\index.php still has the ReadOnly attribute
[X]     [feature_telnet      ] the optional TelnetClient feature is still enabled
[X]     [feature_tftp        ] the optional TFTP feature is still enabled
[X]     [dos_task            ] scheduled task 'Redhavi-ccdcscoring' still exists
[X]     [dos_executable      ] scoring executable still exists at 'C:\ProgramData\CCDC-Lab\ccdcscoring.exe'

=== FINAL RESULT ===
Total:       13
Passed:      0
Remaining:   13
Errors:      0
Score:       0%
```
