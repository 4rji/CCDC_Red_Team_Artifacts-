# Redhavi Cleanup Task

## Objective

The system was prepared as a CCDC lab with several insecure configurations. Your task is to investigate the system, identify suspicious changes, and leave it in a clean state.

Do not assume that every problem is in one place. Review users, services, scheduled tasks, web files, permissions, installed packages, and persistence mechanisms.

## Rules

- Document each finding before changing it.
- Do not delete evidence without understanding what it does.
- Make small changes and verify the system again after each group of changes.
- Do not use automated cleanup scripts unless you can explain what they modify.
- At the end, run the lab checker and compare the result.

## Areas to Review

### Users and Privileges

- Local accounts that should not exist.
- Accounts with interactive shells.
- Users added to administrative groups.
- Weak or forced passwords.
- Service accounts used as regular users.

### SSH

- `authorized_keys` files for sensitive accounts.
- Permissions and special attributes on SSH files.
- Unauthorized public keys.
- SSH configuration that permits overly broad access.

### Scheduled Tasks

- Root's crontab.
- Files under system cron paths.
- Jobs that download files from the network.
- Recurring jobs that restore malicious changes.

### Web and PHP

- Unexpected content under `/var/www`.
- Recently modified PHP files.
- Use of dangerous PHP functions.
- Files that permit operating-system command execution.
- Duplicate copies of the same suspicious page.

### Services

- Enabled services that do not match the system's role.
- Recently started services.
- Insecure file-transfer services.
- Active web services with unknown content.

### Packages

- Clients or servers for insecure protocols.
- Recently installed packages.
- Packages that do not fit the machine's intended function.
- Differences between the baseline and packages added during the incident.

### Permissions and Attributes

- Files marked immutable.
- Sensitive files with overly broad permissions.
- Directories where unprivileged users can write executable content.
- System files modified without justification.

### Network

- Open ports.
- Processes listening on external interfaces.
- Repeated outbound connections.
- Services accepting connections from unexpected networks.

### Evidence of Persistence

- Mechanisms that restore files after deletion.
- Changes that survive restarts.
- Automatic downloads from internal or external hosts.
- Hidden files or nonstandard locations.

## Deliverable

Prepare a short summary containing:

- Primary findings.
- Risk associated with each finding.
- Changes performed.
- Final verification.
- Items requiring follow-up.

## Final Hint

If a check fails, do not treat it as a direct answer. Use it as a starting point to investigate why that state exists and what keeps it active.
