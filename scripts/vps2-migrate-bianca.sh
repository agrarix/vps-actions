#!/bin/bash
# scripts/vps2-migrate-bianca.sh
# Migrate biancawennink.nl to vps2.agrarix.net (212.227.209.36)
# Run on fabrix (automation@192.168.178.40)
set -e

VPS="automation@vps2.agrarix.net"
VSSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $VPS"
PRES="automation@192.168.178.44"
PSSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $PRES"
NAS_DIR="/mnt/nas/WWW/domains/biancawennink.nl/pages"
VHOST_DIR="/var/www/vhosts/biancawennink.nl/html"

echo "==> [1/6] Directories on vps2"
$VSSH "sudo mkdir -p $VHOST_DIR /home/automation/bin /home/automation/log /home/automation/etc"
$VSSH "sudo chown -R automation:automation /var/www/vhosts/biancawennink.nl /home/automation/bin /home/automation/log /home/automation/etc"
$VSSH "sudo chmod 755 /var/www/vhosts/biancawennink.nl /var/www/vhosts/biancawennink.nl/html"

echo "==> [2/6] SSL Certificate presentix -> vps2"
$PSSH "sudo tar czf - -C /etc/letsencrypt live/biancawennink.nl archive/biancawennink.nl renewal/biancawennink.nl.conf" | \
  $VSSH "sudo tar xzf - -C /etc/letsencrypt"
$VSSH "sudo sed -i -e 's/^authenticator = .*/authenticator = apache/' -e 's/^installer = .*/installer = apache/' /etc/letsencrypt/renewal/biancawennink.nl.conf"
$VSSH "sudo grep -q '^installer = ' /etc/letsencrypt/renewal/biancawennink.nl.conf || sudo sed -i '/^authenticator = apache/a installer = apache' /etc/letsencrypt/renewal/biancawennink.nl.conf"

echo "==> [3/6] Sync web files NAS -> vps2"
rsync -avz --delete \
  -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes" \
  "$NAS_DIR/" "$VPS:$VHOST_DIR/"
scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
  "$HOME/proxmox-pve/etc/upd_biancawennink.dates" \
  "$VPS:/home/automation/etc/upd_biancawennink.dates"
$VSSH "sudo chown -R automation:automation $VHOST_DIR /home/automation/etc/upd_biancawennink.dates && sudo chmod -R u=rwX,go=rX $VHOST_DIR"

echo "==> [4/6] Deploy updater script to vps2"
scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
  "$HOME/proxmox-pve/scripts/vps-sites/upd_biancawennink.sh" \
  "$VPS:/home/automation/bin/upd_biancawennink.sh"
$VSSH "chmod 755 /home/automation/bin/upd_biancawennink.sh"

echo "==> [5/6] Apache2 VirtualHosts on vps2"
cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/biancawennink.nl.conf > /dev/null"
<VirtualHost *:80>
    ServerAdmin webadmin@agrarix.net
    ServerName biancawennink.nl
    ServerAlias www.biancawennink.nl
    DocumentRoot /var/www/vhosts/biancawennink.nl/html

    <Directory /var/www/vhosts/biancawennink.nl/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        DirectoryIndex index.html index.htm default.htm default.html
    </Directory>

    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^/?(.*) https://%{HTTP_HOST}/$1 [R=301,L]

    ErrorLog ${APACHE_LOG_DIR}/biancawennink.nl_error.log
    CustomLog ${APACHE_LOG_DIR}/biancawennink.nl_access.log combined
</VirtualHost>
EOF

cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/biancawennink.nl-le-ssl.conf > /dev/null"
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerAdmin webadmin@agrarix.net
    ServerName biancawennink.nl
    ServerAlias www.biancawennink.nl
    DocumentRoot /var/www/vhosts/biancawennink.nl/html

    <Directory /var/www/vhosts/biancawennink.nl/html>
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

    SSLCertificateFile /etc/letsencrypt/live/biancawennink.nl/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/biancawennink.nl/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ErrorLog ${APACHE_LOG_DIR}/biancawennink.nl_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/biancawennink.nl_ssl_access.log combined
</VirtualHost>
</IfModule>
EOF

$VSSH "sudo a2ensite biancawennink.nl.conf biancawennink.nl-le-ssl.conf"
$VSSH "sudo apache2ctl configtest && sudo systemctl reload apache2"

echo "==> [6/6] Run updater, configure crontabs & presentix proxy"
# Run updater on vps2
$VSSH "/home/automation/bin/upd_biancawennink.sh"

# Setup cron on vps2
$VSSH "bash -c '
(crontab -l 2>/dev/null | grep -v upd_biancawennink.sh ; echo \"01 01 * * * /home/automation/bin/upd_biancawennink.sh >/dev/null 2>&1\") | crontab -
'"

# Remove updater from fabrix cron
(crontab -l 2>/dev/null | grep -v 'upd_biancawennink.sh' || true) | crontab -

# Deploy presentix proxy vhost
scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
  "$HOME/proxmox-pve/etc/presentix/biancawennink.nl.conf" \
  "$PRES:/tmp/biancawennink.nl.conf"
$PSSH "sudo mv /tmp/biancawennink.nl.conf /etc/nginx/sites-available/biancawennink.nl.conf && sudo nginx -t && sudo systemctl reload nginx"

echo "--- Verification on vps2 ---"
$VSSH "grep -i 'generator' $VHOST_DIR/index.html"
$VSSH "curl -k -s -o /dev/null -w 'HTTP Response Code: %{http_code}\n' -H 'Host: biancawennink.nl' https://127.0.0.1/"
$VSSH "crontab -l | grep biancawennink"

echo "==> SUCCESS: biancawennink.nl successfully migrated to vps2.agrarix.net!"
