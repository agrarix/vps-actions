#!/bin/bash
# scripts/vps2-migrate-wennink.sh
# Migrate www.wennink.eu (+ wennink.eu) and user pjheise from agrarix.it (85.214.248.88) to vps2.agrarix.net (212.227.209.36)
# Run on fabrix (automation@192.168.178.40)
set -e

VPS="automation@vps2.agrarix.net"
VSSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $VPS"
AGRARIX="root@85.214.248.88"
ASSH="ssh -p 2223 -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $AGRARIX"
VHOST_DIR="/var/www/vhosts/www.wennink.eu/html"

echo "==> [1/7] Create group 'wennink' and user 'pjheise' on vps2"
$VSSH "sudo getent group wennink >/dev/null || sudo groupadd -g 1013 wennink"
$VSSH "sudo id -u pjheise >/dev/null 2>&1 || sudo useradd -u 1012 -g wennink -G www-data -d $VHOST_DIR -s /bin/bash -c 'pjheise@gmail.com' -M pjheise"
# Inject password hash (same password as agrarix.it)
$VSSH 'sudo usermod -p '\''$6$oyANarNI$gtqMvDrKZs2Z0Ey.kjvi5YLga/NcgfKdjNsmAiBk/5WOeYyLKKfrsX1sue1SbgETcSqZo1oHImwoCZCveCD8L0'\'' pjheise'

echo "==> [2/7] Create vhost directory structure on vps2"
$VSSH "sudo mkdir -p /var/www/vhosts/www.wennink.eu"
$VSSH "sudo ln -sfn /var/www/vhosts/www.wennink.eu /var/www/vhosts/wennink.eu"

echo "==> [3/7] Transfer SSL Certificates from agrarix.it -> vps2"
$ASSH "tar czf - -C /etc/letsencrypt live/www.wennink.eu archive/www.wennink.eu renewal/www.wennink.eu.conf live/wennink.eu archive/wennink.eu renewal/wennink.eu.conf" | \
  $VSSH "sudo tar xzf - -C /etc/letsencrypt"
$VSSH "sudo sed -i -e 's/^authenticator = .*/authenticator = apache/' -e 's/^installer = .*/installer = apache/' /etc/letsencrypt/renewal/www.wennink.eu.conf /etc/letsencrypt/renewal/wennink.eu.conf"
$VSSH "sudo grep -q '^installer = ' /etc/letsencrypt/renewal/www.wennink.eu.conf || sudo sed -i '/^authenticator = apache/a installer = apache' /etc/letsencrypt/renewal/www.wennink.eu.conf"
$VSSH "sudo grep -q '^installer = ' /etc/letsencrypt/renewal/wennink.eu.conf || sudo sed -i '/^authenticator = apache/a installer = apache' /etc/letsencrypt/renewal/wennink.eu.conf"

echo "==> [4/7] Sync web files from agrarix.it -> vps2"
$ASSH "tar czf - -C /var/www/vhosts www.wennink.eu" | \
  $VSSH "sudo tar xzf - -C /var/www/vhosts"
$VSSH "sudo chown -R pjheise:wennink /var/www/vhosts/www.wennink.eu"
$VSSH "sudo chmod -R 775 /var/www/vhosts/www.wennink.eu"
$VSSH "sudo mkdir -p $VHOST_DIR/.ssh && sudo chown pjheise:wennink $VHOST_DIR/.ssh && sudo chmod 700 $VHOST_DIR/.ssh"

echo "==> [5/7] Deploy Apache2 VirtualHosts on vps2"
cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/wennink.eu.conf > /dev/null"
<VirtualHost *:80>
    ServerAdmin webadmin@agrarix.net
    ServerName www.wennink.eu
    ServerAlias wennink.eu
    DocumentRoot /var/www/vhosts/www.wennink.eu/html

    <Directory /var/www/vhosts/www.wennink.eu/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        DirectoryIndex index.html index.htm default.htm default.html
    </Directory>

    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^/?(.*) https://%{HTTP_HOST}/$1 [R=301,L]

    ErrorLog ${APACHE_LOG_DIR}/wennink.eu_error.log
    CustomLog ${APACHE_LOG_DIR}/wennink.eu_access.log combined
</VirtualHost>
EOF

cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/wennink.eu-le-ssl.conf > /dev/null"
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerAdmin webadmin@agrarix.net
    ServerName www.wennink.eu
    ServerAlias wennink.eu
    DocumentRoot /var/www/vhosts/www.wennink.eu/html

    <Directory /var/www/vhosts/www.wennink.eu/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        DirectoryIndex index.html index.htm default.htm default.html
    </Directory>

    <IfModule mod_rewrite.c>
        RewriteEngine On
        RewriteCond %{HTTP_USER_AGENT} "android|blackberry|googlebot-mobile|iemobile|ipad|iphone|ipod|opera mobile|palmos|webos" [NC]
        RewriteRule "^(.*)\.html$" "$1.htm" [L]
    </IfModule>

    <Location "/webalizer">
        Require all denied
    </Location>

    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>

    SSLCertificateFile /etc/letsencrypt/live/www.wennink.eu/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/www.wennink.eu/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ErrorLog ${APACHE_LOG_DIR}/wennink.eu_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/wennink.eu_ssl_access.log combined
</VirtualHost>
</IfModule>
EOF

$VSSH "sudo a2ensite wennink.eu.conf wennink.eu-le-ssl.conf"
$VSSH "sudo apache2ctl configtest && sudo systemctl reload apache2"

echo "==> [6/7] Verification on vps2"
$VSSH "id pjheise"
$VSSH "ls -ld $VHOST_DIR"
$VSSH "curl -k -s -o /dev/null -w 'HTTP Response Code (www.wennink.eu): %{http_code}\n' -H 'Host: www.wennink.eu' https://127.0.0.1/"
$VSSH "curl -k -s -o /dev/null -w 'HTTP Response Code (wennink.eu): %{http_code}\n' -H 'Host: wennink.eu' https://127.0.0.1/"

echo "==> [7/7] Scan vhosts on vps2 for Presentix Dashboard"
python3 "$HOME/proxmox-pve/scripts/scan-vps2-vhosts.py" || true

echo "==> SUCCESS: www.wennink.eu and user pjheise migrated to vps2.agrarix.net!"
echo "NOTE: Update DNS A-records for www.wennink.eu and wennink.eu at Mijndomein to 212.227.209.36."
