#!/bin/bash
# ==============================================================================
# CCDC Blue Team Vulnerable PHP Lab Installer
# Target Directory: /var/www/html/ and /var/www/html/uploads/
# ==============================================================================

# 1. Ensure the script runs as root
if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (sudo ./install_vuln_php.sh)"
    exit 1
fi

WEB_ROOT="/var/www/html"
UPLOADS_DIR="/var/www/html/uploads"
REPORTES_DIR="/var/www/html/reportes"
TMP_DIR="/tmp/ccdc_php_repos_$$"

echo "[*] Preparing directories in ${WEB_ROOT}..."
mkdir -p "$WEB_ROOT"
mkdir -p "$UPLOADS_DIR"
mkdir -p "$REPORTES_DIR"
mkdir -p "$TMP_DIR"

# Ensure git is installed
if ! command -v git &> /dev/null; then
    echo "[*] Installing git..."
    apt-get update -y && apt-get install -y git
fi

# 2. Clone vulnerable PHP repositories into temporary directory
echo "[*] Cloning vulnerable PHP lab repositories..."
git clone --depth 1 https://github.com/rubennati/vulnerable-php-code-examples.git "$TMP_DIR/vulnerable-php-code-examples" || true
git clone --depth 1 https://github.com/sarjanpatel22/web-app-security-lab.git "$TMP_DIR/web-app-security-lab" || true

# 3. Copy all PHP files from the cloned repositories into /var/www/html/
echo "[*] Copying vulnerable PHP pages to ${WEB_ROOT}..."
find "$TMP_DIR" -type f -name "*.php" -exec cp -f {} "$WEB_ROOT/" \;

# 4. Generate standardized CCDC challenges connected to /uploads/ and /reportes/
echo "[*] Generating download.php, ping_tool.php, visor.php, and upload.php..."

# Challenge A: download.php (Directory Traversal / Arbitrary File Download)
cat << 'EOF' > "$WEB_ROOT/download.php"
<?php
// CCDC CHALLENGE: Report Download (Vulnerable to Directory Traversal / LFI)
// Player Objective: Restrict downloads to /var/www/html/reportes/ using basename() and realpath()
$directory = "/var/www/html/reportes/";
if (isset($_GET['file'])) {
    $file = $_GET['file'];
    // VULNERABLE: Direct concatenation allows escaping via ../../../../etc/passwd
    $path = $directory . $file;
    if (file_exists($path)) {
        header('Content-Type: text/plain');
        readfile($path);
        exit;
    } elseif (file_exists($file)) {
        header('Content-Type: text/plain');
        readfile($file);
        exit;
    } else {
        echo "File not found: " . htmlspecialchars($file);
    }
} else {
    echo "Usage: download.php?file=diario.txt";
}
?>
EOF

# Challenge B: ping_tool.php (Command Injection)
cat << 'EOF' > "$WEB_ROOT/ping_tool.php"
<?php
// CCDC CHALLENGE: Network Diagnostic Tool (Vulnerable to Command Injection)
// Player Objective: Validate IP with filter_var() and escape arguments with escapeshellarg()
$output = "";
if (isset($_REQUEST['ip'])) {
    $target = $_REQUEST['ip'];
    // VULNERABLE: Unsanitized concatenation passed directly to shell_exec()
    $output = shell_exec("ping -c 3 " . $target);
}
?>
<!DOCTYPE html>
<html>
<head><title>CCDC - Network Diagnostic Tool</title></head>
<body>
    <h3>Check Server Connectivity</h3>
    <form method="POST">
        IP or Host: <input type="text" name="ip" placeholder="127.0.0.1">
        <button type="submit">Ping</button>
    </form>
    <pre><?php echo htmlspecialchars($output ?? ''); ?></pre>
</body>
</html>
EOF

# Challenge C: visor.php (Path Traversal / LFI)
cat << 'EOF' > "$WEB_ROOT/visor.php"
<?php
// CCDC CHALLENGE: System Log & Report Viewer (Vulnerable to Path Traversal / LFI)
// Player Objective: Restrict file reading strictly to /var/www/html/reportes/
$content = "";
if (isset($_GET['archivo'])) {
    $file = $_GET['archivo'];
    // VULNERABLE: Direct path concatenation allows ../../../../etc/passwd
    $path = "/var/www/html/reportes/" . $file;
    if (file_exists($path)) {
        $content = file_get_contents($path);
    } else {
        $content = "Report not found: " . htmlspecialchars($path);
    }
}
?>
<!DOCTYPE html>
<html>
<head><title>CCDC - System Report Viewer</title></head>
<body>
    <h3>View System Report</h3>
    <p><a href="?archivo=diario.txt">View daily report</a></p>
    <pre><?php echo htmlspecialchars($content); ?></pre>
</body>
</html>
EOF

# Challenge D: upload.php (Unrestricted File Upload to /var/www/html/uploads/)
cat << 'EOF' > "$WEB_ROOT/upload.php"
<?php
// CCDC CHALLENGE: Avatar Upload (Vulnerable to Unrestricted File Upload)
// Player Objective: Validate real image MIME/extension and disable PHP execution in /uploads/
$message = "";
$field = isset($_FILES['avatar']) ? 'avatar' : (isset($_FILES['archivo']) ? 'archivo' : null);

if ($field !== null && isset($_FILES[$field]['tmp_name'])) {
    $filename = $_FILES[$field]['name'];
    $destination = "/var/www/html/uploads/" . $filename;
    // VULNERABLE: Allows uploading .php webshells directly into /uploads/
    if (move_uploaded_file($_FILES[$field]['tmp_name'], $destination)) {
        chmod($destination, 0777);
        $message = "File uploaded successfully to: uploads/" . htmlspecialchars($filename);
    } else {
        $message = "Error uploading file.";
    }
}
?>
<!DOCTYPE html>
<html>
<head><title>CCDC - Upload Avatar</title></head>
<body>
    <h3>Upload Profile Picture</h3>
    <form method="POST" enctype="multipart/form-data">
        <input type="file" name="avatar">
        <button type="submit">Upload Image</button>
    </form>
    <p><?php echo $message; ?></p>
</body>
</html>
EOF

# Create legitimate report file for SLA verification
echo "CCDC Daily System Report - All services operating normally." > "$REPORTES_DIR/diario.txt"

# Ensure ccdc-lab.php exists if not already created by instservices
if [ ! -f "$WEB_ROOT/ccdc-lab.php" ]; then
    echo "<?php echo '<h1>CCDC Lab Portal</h1>'; ?>" > "$WEB_ROOT/ccdc-lab.php"
fi

# 5. Apply intentionally vulnerable permissions (root:root + chmod 777)
echo "[*] Applying root:root ownership and insecure 777 permissions in ${WEB_ROOT}..."
chown -R root:root "$WEB_ROOT"
chmod 777 "$WEB_ROOT"
chmod 777 "$WEB_ROOT"/*.php
chmod -R 777 "$UPLOADS_DIR" "$REPORTES_DIR"

# 6. Clean up temporary directory
rm -rf "$TMP_DIR"

echo "[+] Installation complete. Vulnerable PHP files deployed in ${WEB_ROOT} with 777 permissions:"
ls -la "$WEB_ROOT"/*.php