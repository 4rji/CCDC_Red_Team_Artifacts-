# Repository Guidelines

## Project Structure & Module Organization

This repository is intentionally flat. Linux scenario seeders and checkers are executable Bash files in the root (`redhavi`, `redhavi-fedora`, and `redhavi-check*`). Windows equivalents use PowerShell (`redhaviwin.ps1`, `redhavi-checkWin.ps1`). `redhavi-monitor` is a standalone Python 3 dashboard. The `ecomredhavi*` scripts create web/database practice labs, while `redhavi-task.md`, `README.md`, and `INSTALLATION.md` contain student and operator documentation. `apollo1.exe` and `poseidon.bin` are zero-byte placeholders, not working payloads. Generated artifacts belong under `build/` and should not be committed unless explicitly required.

## Build, Test, and Development Commands

There is no project-wide build system or dependency lockfile. Run focused checks from the repository root:

```bash
bash -n redhavi redhavi-check redhavi-fedora redhavi-check-fedora
python3 -m py_compile redhavi-monitor
shellcheck redhavi redhavi-check redhavi-* ecomredhavi*  # when installed
shc -f redhavi-check-shc -o build/redhavi-check
```

On Windows, validate scripts with PowerShell 5.1 and build the checker using `./redhavi-checkWin-ps2exe.ps1 -InstallPs2Exe`. Follow `INSTALLATION.md` for platform-specific packaging and deployment.

## Coding Style & Naming Conventions

Use four spaces in Python and PowerShell; follow the existing four-space function-body indentation in Bash. Shell scripts should use `#!/usr/bin/env bash`, quote expansions, prefer `printf`, and enable strict modes appropriate to their role. Use `snake_case` for Bash/Python functions and variables, and approved PowerShell Verb-Noun function names. Preserve established filenames, including the historical `redhavi-check-federo-shc` spelling. Keep user-facing messages concise and identify errors clearly.

## Testing Guidelines

No automated test framework or coverage threshold currently exists. At minimum, run syntax checks for every edited script. Exercise `--help` and dry-run modes where available; `redhavi-fedora` is dry-run by default. Test stateful or privileged behavior only in isolated, disposable VMs matching the target OS. Confirm checker totals and exit codes (`0` clean, `1` findings, `2` infrastructure error where supported).

## Commit & Pull Request Guidelines

History currently contains only `Initial commit`, so no mature convention exists. Use short, imperative subjects such as `Harden Fedora checker state validation`. Keep commits scoped to one logical change. Pull requests should describe affected platforms and scenarios, list validation commands, document changed check counts or state versions, and include dashboard screenshots when UI output changes.

## Security & Configuration

These scripts intentionally create vulnerable services, accounts, and persistence. Never run scenario seeders on production systems or untrusted networks. Do not commit live Mythic payloads, private keys, credentials, state files, or environment-specific infrastructure addresses. Use pinned hashes for downloaded exercise artifacts and restore VM snapshots after testing.
