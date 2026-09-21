# Redhavi — CCDC Training Lab Suite

This repository contains scenarios, assessment checkers, and monitoring tools that I use as the captain of a **CCDC (Collegiate Cyber Defense Competition)** team to prepare realistic defensive security and incident-response exercises.

The project helps our team learn to identify insecure configurations, remove persistence, protect services, and validate the recovery of Linux and Windows systems under pressure. These scenarios reproduce controlled competition conditions; they are not tools for attacking real systems.

> [!WARNING]
> **For authorized training only.** Some scripts deliberately create weak accounts, scheduled tasks, insecure services, SSH access, and vulnerable web content. Run them only on disposable virtual machines in an isolated network with a recoverable snapshot.

## Training Objectives

- Practice hardening Ubuntu, Fedora, and Windows systems.
- Detect and remove persistence mechanisms.
- Audit accounts, services, scheduled tasks, SSH keys, and web content.
- Secure Apache, PHP, and MySQL in e-commerce training labs.
- Measure progress with read-only checkers and a canary dashboard.
- Improve team communication and task delegation during an incident.

## Main Components

| Component | Description |
| --- | --- |
| `redhavi` / `redhavi-fedora` | Prepare intentionally vulnerable Linux scenarios. |
| `redhavi-check*` | Assess cleanup and hardening on Ubuntu or Fedora. |
| `redhaviwin.ps1` | Prepares the Windows training scenario. |
| `redhavi-checkWin.ps1` | Assesses the Windows scenario without modifying it. |
| `redhavi-monitor` | Runs the canary check-in server and live dashboard. |
| `ecomredhavi*` | Provide Apache, PHP, and MySQL security labs. |
| `redhavi-task.md` | Contains the assignment given to participants. |
| `INSTALLATION.md` | Provides detailed build, installation, and operation instructions. |

The included `apollo1.exe` and `poseidon.bin` files are empty placeholders. **They do not contain executable payloads.**

## Recommended Lab Workflow

1. Create a disposable VM that matches the scenario and take a snapshot.
2. Isolate it from production networks and the Internet, except for controlled resources required by the exercise.
3. Run the appropriate scenario preparation script as the instructor.
4. Give the team `redhavi-task.md` and the corresponding checker.
5. Start `redhavi-monitor` on a separate instructor system when using canaries.
6. Review the results, document findings, and restore the snapshot after the exercise.

Scenario preparation scripts **modify the target system**. Checkers are read-only, but they require elevated privileges to inspect every scored artifact.

## Quick Start

Before deployment, validate script syntax from the repository root:

```bash
bash -n redhavi redhavi-check redhavi-fedora redhavi-check-fedora
python3 -m py_compile redhavi-monitor
```

To preview the Fedora scenario without applying changes:

```bash
./redhavi-fedora
```

Read [INSTALLATION.md](INSTALLATION.md) before compiling checkers, preparing Windows, or running a complete scenario.

## Responsible-Use Principles

- Obtain explicit authorization before every exercise.
- Never deploy these artifacts on personal or production systems.
- Do not store credentials, private keys, or live payloads in this repository.
- Verify downloaded exercise artifacts with SHA-256 hashes.
- Keep training infrastructure isolated and remove its data after the exercise.

## Contributing

Improvements to scenarios, checkers, and documentation are welcome. Keep each change focused, identify the affected platform, and document how it was validated. See [AGENTS.md](AGENTS.md) for repository conventions.

## Disclaimer

This is an independent educational project. It is not officially affiliated with CCDC and does not replace the rules, images, or infrastructure provided by competition organizers.
