#!/bin/bash
# ==============================================================================
# CCDC Blue Team Automated Remediation & Lab Toggle Script (solucion_blueteam.sh)
# Target Directory: /var/www/html/
#
# Usage (run as root on the Apache2 server):
#   sudo ./solucion_blueteam.sh           # Default: Patches all vulns (100/100 pts)
#   sudo ./solucion_blueteam.sh --patch   # Patches all vulns & permissions (100/100 pts)
#   sudo ./solucion_blueteam.sh --vuln    # Reverts server to vulnerable state (0/100 pts)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (sudo ./solucion_blueteam.sh)"
    exit 1
fi

WEB_ROOT="/var/www/html"
UPLOADS_DIR="/var/www/html/uploads"
REPORTES_DIR="/var/www/html/reportes"
APACHE_CONF="/etc/apache2/conf-available/ccdc-uploads-hardening.conf"

MODE="${1:---patch}"

mkdir -p "$WEB_ROOT" "$UPLOADS_DIR" "$REPORTES_DIR"

# Ensure daily report exists for SLA checks
if [ ! -f "$REPORTES_DIR/diario.txt" ]; then
    echo "CCDC Daily System Report - All services operating normally." > "$REPORTES_DIR/diario.txt"
fi

apply_patches() {
    echo "=============================================================================="
    echo " [*] APPLYING BLUE TEAM REMEDIATION (TARGET: 100 / 100 POINTS)"
    echo "=============================================================================="

    # --------------------------------------------------------------------------
    # 1. Clean Defacement in ccdc-lab.php & Remove Active Webshells in /uploads/
    # --------------------------------------------------------------------------
    echo "[*] Cleaning defacement on ccdc-lab.php and removing webshells in /uploads/..."
    if [ -f "$WEB_ROOT/ccdc-lab.php" ]; then
        sed -i '/Archivo modificado/d; /Modificado por www-data/d; /Modified by www-data/d; /chmod 777/d' "$WEB_ROOT/ccdc-lab.php"
    else
        cat << 'EOF' > "$WEB_ROOT/ccdc-lab.php"
<?php
// CCDC Main Portal - Intact & Secure
echo "<h1>CCDC Lab Portal</h1><p>Status: Operational</p>";
?>
EOF
    fi

    # Remove any uploaded .php backdoors or probes inside /uploads/
    find "$UPLOADS_DIR" -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) -delete

    # --------------------------------------------------------------------------
    # 2. Patch ping_tool.php (Fixes Command Injection while preserving Ping SLA)
    # --------------------------------------------------------------------------
    echo "[*] Patching ping_tool.php (Strict IP validation + escapeshellarg)..."
    cat << 'EOF' > "$WEB_ROOT/ping_tool.php"
<?php
// CCDC CHALLENGE PATCHED: Network Diagnostic Tool (Command Injection Fixed)
$output = "";
if (isset($_REQUEST['ip'])) {
    $target = trim($_REQUEST['ip']);

    // Strictly validate IPv4/IPv6 address format
    if (filter_var($target, FILTER_VALIDATE_IP)) {
        $safe_ip = escapeshellarg($target);
        $output = shell_exec("ping -c 3 " . $safe_ip);
    } else {
        http_response_code(400);
        $output = "Security Block: Invalid IP address format.";
    }
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
    <pre><?php echo htmlspecialchars($output ?? '', ENT_QUOTES, 'UTF-8'); ?></pre>
</body>
</html>
EOF

    # --------------------------------------------------------------------------
    # 3. Patch visor.php (Fixes Path Traversal / LFI while preserving Report SLA)
    # --------------------------------------------------------------------------
    echo "[*] Patching visor.php (basename + realpath directory confinement)..."
    cat << 'EOF' > "$WEB_ROOT/visor.php"
<?php
// CCDC CHALLENGE PATCHED: System Report Viewer (Path Traversal Fixed)
$content = "";
$base_dir = realpath("/var/www/html/reportes");

if (isset($_GET['archivo'])) {
    $clean_name = basename($_GET['archivo']);
    $target_path = realpath($base_dir . DIRECTORY_SEPARATOR . $clean_name);

    if ($target_path !== false && strpos($target_path, $base_dir . DIRECTORY_SEPARATOR) === 0 && is_file($target_path)) {
        $content = file_get_contents($target_path);
    } else {
        http_response_code(403);
        $content = "Access denied: Invalid report path.";
    }
}
?>
<!DOCTYPE html>
<html>
<head><title>CCDC - System Report Viewer</title></head>
<body>
    <h3>View System Report</h3>
    <p><a href="?archivo=diario.txt">View daily report</a></p>
    <pre><?php echo htmlspecialchars($content, ENT_QUOTES, 'UTF-8'); ?></pre>
</body>
</html>
EOF

    # --------------------------------------------------------------------------
    # 4. Patch download.php (Fixes Arbitrary File Download / LFI)
    # --------------------------------------------------------------------------
    echo "[*] Patching download.php (basename + realpath confinement)..."
    cat << 'EOF' > "$WEB_ROOT/download.php"
<?php
// CCDC CHALLENGE PATCHED: Report Download (Directory Traversal Fixed)
$base_dir = realpath("/var/www/html/reportes");

if (isset($_GET['file'])) {
    $clean_name = basename($_GET['file']);
    $target_path = realpath($base_dir . DIRECTORY_SEPARATOR . $clean_name);

    if ($target_path !== false && strpos($target_path, $base_dir . DIRECTORY_SEPARATOR) === 0 && is_file($target_path)) {
        header('Content-Type: text/plain');
        header('Content-Disposition: attachment; filename="' . $clean_name . '"');
        readfile($target_path);
        exit;
    } else {
        http_response_code(403);
        echo "Access denied: File not permitted.";
    }
} else {
    echo "Usage: download.php?file=diario.txt";
}
?>
EOF

    # --------------------------------------------------------------------------
    # 5. Patch upload.php & Disable PHP Execution in /uploads/
    # --------------------------------------------------------------------------
    echo "[*] Patching upload.php (MIME + image header verification + safe filename)..."
    cat << 'EOF' > "$WEB_ROOT/upload.php"
<?php
// CCDC CHALLENGE PATCHED: Secure Avatar Upload (Blocks PHP Webshells)
$message = "";
$field = isset($_FILES['avatar']) ? 'avatar' : (isset($_FILES['archivo']) ? 'archivo' : null);

if ($field !== null && isset($_FILES[$field]) && $_FILES[$field]['error'] === UPLOAD_ERR_OK) {
    $tmp_name = $_FILES[$field]['tmp_name'];
    $orig_name = $_FILES[$field]['name'];
    $ext = strtolower(pathinfo($orig_name, PATHINFO_EXTENSION));

    $allowed_exts = ['gif', 'jpg', 'jpeg', 'png'];
    $img_info = @getimagesize($tmp_name);
    $allowed_mimes = ['image/gif', 'image/jpeg', 'image/png'];

    if (in_array($ext, $allowed_exts, true) && $img_info !== false && in_array($img_info['mime'], $allowed_mimes, true)) {
        $safe_name = "avatar_" . bin2hex(random_bytes(6)) . "." . $ext;
        $destination = "/var/www/html/uploads/" . $safe_name;

        if (move_uploaded_file($tmp_name, $destination)) {
            chmod($destination, 0640);
            $message = "File uploaded successfully to: uploads/" . htmlspecialchars($safe_name, ENT_QUOTES, 'UTF-8');
        } else {
            http_response_code(500);
            $message = "Error saving verified image.";
        }
    } else {
        http_response_code(403);
        $message = "Security Block: Only valid GIF, JPG, and PNG images are permitted.";
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

    echo "[*] Disabling script execution inside ${UPLOADS_DIR} via Apache2..."
    cat << 'EOF' > "$UPLOADS_DIR/.htaccess"
<FilesMatch "\.(?i:php|php3|php4|php5|phtml|phar|pl|py|cgi|sh)$">
    Require all denied
</FilesMatch>
Options -ExecCGI -Indexes
EOF

    if [ -d "/etc/apache2/conf-available" ]; then
        cat << 'EOF' > "$APACHE_CONF"
<Directory "/var/www/html/uploads">
    Options -ExecCGI -Indexes
    AllowOverride None
    <FilesMatch "\.(?i:php|php3|php4|php5|phtml|phar|pl|py|cgi|sh)$">
        Require all denied
    </FilesMatch>
</Directory>
EOF
        a2enconf ccdc-uploads-hardening >/dev/null 2>&1 || true
        systemctl reload apache2 >/dev/null 2>&1 || service apache2 reload >/dev/null 2>&1 || true
    fi

    # --------------------------------------------------------------------------
    # 6. Harden File Permissions (Remove 777 from all PHP files and directories)
    # --------------------------------------------------------------------------
    echo "[*] Hardening filesystem permissions in ${WEB_ROOT} (644 on files, 755 on dirs)..."
    chown -R root:www-data "$WEB_ROOT"
    find "$WEB_ROOT" -type d -exec chmod 755 {} \;
    find "$WEB_ROOT" -type f -exec chmod 644 {} \;

    # Allow www-data group to write verified images into /uploads/ without world-writable bit
    chown -R root:www-data "$UPLOADS_DIR"
    chmod 775 "$UPLOADS_DIR"
    chmod 644 "$UPLOADS_DIR/.htaccess"

    echo "[+] Remediation complete! Run ./scorebot_php_validator.sh to verify 100 / 100 POINTS."
}

restore_vulnerable() {
    echo "=============================================================================="
    echo " [!] RESTORING VULNERABLE LAB STATE (TARGET: 0 / 100 POINTS)"
    echo "=============================================================================="

    # Remove Apache uploads hardening
    rm -f "$UPLOADS_DIR/.htaccess"
    if [ -f "$APACHE_CONF" ]; then
        a2disconf ccdc-uploads-hardening >/dev/null 2>&1 || true
        rm -f "$APACHE_CONF"
        systemctl reload apache2 >/dev/null 2>&1 || service apache2 reload >/dev/null 2>&1 || true
    fi

    # Restore vulnerable download.php
    cat << 'EOF' > "$WEB_ROOT/download.php"
<?php
$directory = "/var/www/html/reportes/";
if (isset($_GET['file'])) {
    $file = $_GET['file'];
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

    # Restore vulnerable ping_tool.php
    cat << 'EOF' > "$WEB_ROOT/ping_tool.php"
<?php
$output = "";
if (isset($_REQUEST['ip'])) {
    $target = $_REQUEST['ip'];
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

    # Restore vulnerable visor.php
    cat << 'EOF' > "$WEB_ROOT/visor.php"
<?php
$content = "";
if (isset($_GET['archivo'])) {
    $file = $_GET['archivo'];
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

    # Restore vulnerable upload.php
    cat << 'EOF' > "$WEB_ROOT/upload.php"
<?php
$message = "";
$field = isset($_FILES['avatar']) ? 'avatar' : (isset($_FILES['archivo']) ? 'archivo' : null);

if ($field !== null && isset($_FILES[$field]['tmp_name'])) {
    $filename = $_FILES[$field]['name'];
    $destination = "/var/www/html/uploads/" . $filename;
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

    # Restore insecure 777 permissions across /var/www/html
    chown -R root:root "$WEB_ROOT"
    chmod 777 "$WEB_ROOT"
    chmod 777 "$WEB_ROOT"/*.php
    chmod -R 777 "$UPLOADS_DIR" "$REPORTES_DIR"

    echo "[!] Server restored to vulnerable state (777 permissions + unpatched PHP)."
    echo "    Run ./scorebot_php_validator.sh to verify 0 / 100 POINTS."
}

case "$MODE" in
    --patch|-p)
        apply_patches
        ;;
    --vuln|--reset|-v)
        restore_vulnerable
        ;;
    *)
        echo "Usage: sudo $0 [--patch | --vuln]"
        exit 1
        ;;
esac