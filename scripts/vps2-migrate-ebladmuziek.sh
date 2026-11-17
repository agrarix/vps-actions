#!/bin/bash
# ==============================================================================
# scripts/vps2-migrate-ebladmuziek.sh
# Migrate vijos.e-bladmuziek.nl, e-bladmuziek.nl, www.e-bladmuziek.nl and
# vijos-plus.e-bladmuziek.nl from VPS1 (85.214.248.88) to VPS2 (212.227.209.36)
# Run on fabrix (automation@192.168.178.40) or directly via SSH
# ==============================================================================
set -euo pipefail

VPS2="automation@212.227.209.36"
VSSH="ssh -p 2223 -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes $VPS2"
AGRARIX="root@85.214.248.88"
ASSH="ssh -p 2223 -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes $AGRARIX"

echo "==> [1/6] Setting up vhost directories and symlinks on VPS2..."
$VSSH "sudo ln -sfn /var/www/vhosts/new.e-bladmuziek.nl /var/www/vhosts/vijos.e-bladmuziek.nl"
$VSSH "sudo ln -sfn /var/www/vhosts/new.e-bladmuziek.nl /var/www/vhosts/e-bladmuziek.nl"
$VSSH "sudo ln -sfn /var/www/vhosts/new.e-bladmuziek.nl /var/www/vhosts/www.e-bladmuziek.nl"
$VSSH "sudo ln -sfn /var/www/vhosts/new.e-bladmuziek.nl /var/www/vhosts/vijos-plus.e-bladmuziek.nl"

echo "==> [2/6] Transferring Let's Encrypt SSL certificates from VPS1 -> VPS2..."
$ASSH "tar czf - -C /etc/letsencrypt live/vijos.e-bladmuziek.nl archive/vijos.e-bladmuziek.nl renewal/vijos.e-bladmuziek.nl.conf live/www.e-bladmuziek.nl archive/www.e-bladmuziek.nl renewal/www.e-bladmuziek.nl.conf" | \
  $VSSH "sudo tar xzf - -C /etc/letsencrypt"

$VSSH "
  sudo sed -i -e 's/^authenticator = .*/authenticator = apache/' -e 's/^installer = .*/installer = apache/' /etc/letsencrypt/renewal/vijos.e-bladmuziek.nl.conf /etc/letsencrypt/renewal/www.e-bladmuziek.nl.conf
  sudo grep -q '^installer = ' /etc/letsencrypt/renewal/vijos.e-bladmuziek.nl.conf || sudo sed -i '/^authenticator = apache/a installer = apache' /etc/letsencrypt/renewal/vijos.e-bladmuziek.nl.conf
  sudo grep -q '^installer = ' /etc/letsencrypt/renewal/www.e-bladmuziek.nl.conf || sudo sed -i '/^authenticator = apache/a installer = apache' /etc/letsencrypt/renewal/www.e-bladmuziek.nl.conf
"

echo "==> [3/6] Delta rsync data from VPS1 to VPS2 (preserving local .htaccess)..."
# Stream delta tar excluding .htaccess and Demo/ to avoid overwriting updated paths
$ASSH "tar --exclude='.htaccess' --exclude='Demo' -czf - -C /var/www/vhosts/vijos.e-bladmuziek.nl html" | \
  $VSSH "sudo tar xzf - -C /var/www/vhosts/new.e-bladmuziek.nl"

echo "==> [4/6] Verifying permissions and htpasswd security on VPS2..."
$VSSH "
  sudo chown -R automation:automation /var/www/vhosts/new.e-bladmuziek.nl
  sudo find /var/www/vhosts/new.e-bladmuziek.nl -type d -exec chmod 755 {} +
  sudo find /var/www/vhosts/new.e-bladmuziek.nl -type f -exec chmod 644 {} +

  sudo chown -R automation:automation /home/automation/e-bladmuziek
  sudo chmod 755 /home/automation
  sudo chmod 755 /home/automation/e-bladmuziek
  sudo chgrp -R www-data /home/automation/e-bladmuziek/htpwd
  sudo chmod 770 /home/automation/e-bladmuziek/htpwd
  sudo find /home/automation/e-bladmuziek/htpwd -type f -exec chmod 660 {} +
"

echo "==> [5/6] Deploying Apache2 VirtualHost configurations on VPS2..."

# 1. vijos.e-bladmuziek.nl (+ vijos-plus)
cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/vijos.e-bladmuziek.nl.conf > /dev/null"
<VirtualHost *:80>
    ServerAdmin webadmin@agrarix.net
    ServerName vijos.e-bladmuziek.nl
    ServerAlias vijos-plus.e-bladmuziek.nl

    RewriteEngine On
    RewriteCond %{SERVER_NAME} =vijos-plus.e-bladmuziek.nl
    RewriteRule ^ https://vijos.e-bladmuziek.nl/ViJoS_Plus/ [R=301,L]

    RewriteCond %{HTTPS} !=on
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [R=301,L]

    ErrorLog ${APACHE_LOG_DIR}/vijos.e-bladmuziek.nl_error.log
    CustomLog ${APACHE_LOG_DIR}/vijos.e-bladmuziek.nl_access.log combined
</VirtualHost>

<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerAdmin webadmin@agrarix.net
    ServerName vijos.e-bladmuziek.nl
    ServerAlias vijos-plus.e-bladmuziek.nl
    DocumentRoot /var/www/vhosts/vijos.e-bladmuziek.nl/html

    <Directory /var/www/vhosts/vijos.e-bladmuziek.nl/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    <IfModule mod_rewrite.c>
      RewriteEngine On

      # vijos-plus direct redirect naar ViJoS_Plus sectie
      RewriteCond %{HTTP_HOST} ^vijos-plus\. [NC]
      RewriteRule ^/?$ https://vijos.e-bladmuziek.nl/ViJoS_Plus/ [R=301,L]

      # Mobiele toestellen naar .htm
      RewriteCond %{HTTP_USER_AGENT} "android|blackberry|googlebot-mobile|iemobile|ipad|iphone|ipod|opera mobile|palmos|webos" [NC]
      RewriteRule "^(.*)\.html$" "$1.htm" [L]
    </IfModule>

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/vijos.e-bladmuziek.nl/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/vijos.e-bladmuziek.nl/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ErrorLog ${APACHE_LOG_DIR}/vijos.e-bladmuziek.nl_error.log
    CustomLog ${APACHE_LOG_DIR}/vijos.e-bladmuziek.nl_access.log combined
</VirtualHost>
</IfModule>
EOF

# 2. e-bladmuziek.nl (+ www)
cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/e-bladmuziek.nl.conf > /dev/null"
<VirtualHost *:80>
    ServerAdmin webadmin@agrarix.net
    ServerName e-bladmuziek.nl
    ServerAlias www.e-bladmuziek.nl

    RewriteEngine On
    RewriteRule ^ https://vijos.e-bladmuziek.nl%{REQUEST_URI} [R=301,L]

    ErrorLog ${APACHE_LOG_DIR}/e-bladmuziek.nl_error.log
    CustomLog ${APACHE_LOG_DIR}/e-bladmuziek.nl_access.log combined
</VirtualHost>

<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerAdmin webadmin@agrarix.net
    ServerName e-bladmuziek.nl
    ServerAlias www.e-bladmuziek.nl

    RewriteEngine On
    RewriteRule ^ https://vijos.e-bladmuziek.nl%{REQUEST_URI} [R=301,L]

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/www.e-bladmuziek.nl/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/www.e-bladmuziek.nl/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ErrorLog ${APACHE_LOG_DIR}/e-bladmuziek.nl_error.log
    CustomLog ${APACHE_LOG_DIR}/e-bladmuziek.nl_access.log combined
</VirtualHost>
</IfModule>
EOF

echo "==> [6/6] Enabling sites and testing Apache configuration on VPS2..."
$VSSH "
  sudo a2ensite vijos.e-bladmuziek.nl.conf e-bladmuziek.nl.conf
  sudo apache2ctl configtest
  sudo systemctl reload apache2
"

echo "=============================================================================="
echo "==> VOORBEREIDING SUCCESVOL AFGEROND!"
echo "VPS2 staat 100% gereed met VHosts, SSL certificaten en delta-gesynchroniseerde bestanden."
echo ""
echo "Volgende stap: DNS Cutover bij registrar omzetten naar 212.227.209.36:"
echo "  - vijos.e-bladmuziek.nl      A  212.227.209.36"
echo "  - e-bladmuziek.nl            A  212.227.209.36"
echo "  - www.e-bladmuziek.nl        A  212.227.209.36"
echo "  - vijos-plus.e-bladmuziek.nl A  212.227.209.36"
echo "=============================================================================="
