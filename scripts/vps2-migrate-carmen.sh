#!/bin/bash
# scripts/vps2-migrate-carmen.sh
# Migrate carmenkalbermatten.ch to vps2.agrarix.net (212.227.209.36)
# Run on fabrix (automation@192.168.178.40)
set -e

VPS="automation@vps2.agrarix.net"
VSSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $VPS"
PRES="automation@192.168.178.44"
PSSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $PRES"
NAS_DIR="/mnt/nas/WWW/domains/carmenkalbermatten.ch/pages"
VHOST_DIR="/var/www/vhosts/carmenkalbermatten.ch/html"

echo "==> [1/6] Directories on vps2"
$VSSH "sudo mkdir -p $VHOST_DIR /home/automation/bin /home/automation/log /home/automation/etc"
$VSSH "sudo chown -R automation:automation /var/www/vhosts/carmenkalbermatten.ch /home/automation/bin /home/automation/log /home/automation/etc"
$VSSH "sudo chmod 755 /var/www/vhosts/carmenkalbermatten.ch /var/www/vhosts/carmenkalbermatten.ch/html"

echo "==> [2/6] SSL Certificate presentix -> vps2"
$PSSH "sudo tar czf - -C /etc/letsencrypt live/carmenkalbermatten.ch archive/carmenkalbermatten.ch renewal/carmenkalbermatten.ch.conf" | \
  $VSSH "sudo tar xzf - -C /etc/letsencrypt"
$VSSH "sudo sed -i -e 's/^authenticator = .*/authenticator = apache/' -e 's/^installer = .*/installer = apache/' /etc/letsencrypt/renewal/carmenkalbermatten.ch.conf"
$VSSH "sudo grep -q '^installer = ' /etc/letsencrypt/renewal/carmenkalbermatten.ch.conf || sudo sed -i '/^authenticator = apache/a installer = apache' /etc/letsencrypt/renewal/carmenkalbermatten.ch.conf"

echo "==> [3/6] Sync web files NAS -> vps2"
rsync -avz --delete \
  -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes" \
  "$NAS_DIR/" "$VPS:$VHOST_DIR/"
$VSSH "sudo chown -R automation:automation $VHOST_DIR && sudo chmod -R u=rwX,go=rX $VHOST_DIR"

echo "==> [4/6] Deploy updater script to vps2"
scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
  "$HOME/proxmox-pve/scripts/vps-sites/upd_carmenkalbermatten.sh" \
  "$VPS:/home/automation/bin/upd_carmenkalbermatten.sh"
$VSSH "chmod 755 /home/automation/bin/upd_carmenkalbermatten.sh"

echo "==> [5/6] Apache2 VirtualHosts on vps2"
cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/carmenkalbermatten.ch.conf > /dev/null"
<VirtualHost *:80>
    ServerAdmin webadmin@agrarix.net
    ServerName carmenkalbermatten.ch
    ServerAlias www.carmenkalbermatten.ch
    DocumentRoot /var/www/vhosts/carmenkalbermatten.ch/html

    <Directory /var/www/vhosts/carmenkalbermatten.ch/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        DirectoryIndex index.html index.htm default.htm default.html
    </Directory>

    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^/?(.*) https://%{HTTP_HOST}/$1 [R=301,L]

    ErrorLog ${APACHE_LOG_DIR}/carmenkalbermatten.ch_error.log
    CustomLog ${APACHE_LOG_DIR}/carmenkalbermatten.ch_access.log combined
</VirtualHost>
EOF

cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/carmenkalbermatten.ch-le-ssl.conf > /dev/null"
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerAdmin webadmin@agrarix.net
    ServerName carmenkalbermatten.ch
    ServerAlias www.carmenkalbermatten.ch
    DocumentRoot /var/www/vhosts/carmenkalbermatten.ch/html

    <Directory /var/www/vhosts/carmenkalbermatten.ch/html>
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

    SSLCertificateFile /etc/letsencrypt/live/carmenkalbermatten.ch/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/carmenkalbermatten.ch/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ErrorLog ${APACHE_LOG_DIR}/carmenkalbermatten.ch_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/carmenkalbermatten.ch_ssl_access.log combined
</VirtualHost>
</IfModule>
EOF

$VSSH "sudo a2ensite carmenkalbermatten.ch.conf carmenkalbermatten.ch-le-ssl.conf"
$VSSH "sudo apache2ctl configtest && sudo systemctl reload apache2"

echo "==> [6/6] Run updater, configure crontabs & verify"
# Run updater on vps2
$VSSH "/home/automation/bin/upd_carmenkalbermatten.sh"

# Setup cron on vps2
$VSSH "bash -c '
(crontab -l 2>/dev/null | grep -v upd_carmenkalbermatten.sh ; echo \"11 01 * * * /home/automation/bin/upd_carmenkalbermatten.sh >/dev/null 2>&1\") | crontab -
'"

# Remove updater from fabrix cron
(crontab -l 2>/dev/null | grep -v 'upd_carmenkalbermatten.sh' || true) | crontab -

echo "--- Verification on vps2 ---"
$VSSH "grep -i 'generator' $VHOST_DIR/index.html"
$VSSH "curl -k -s -o /dev/null -w 'HTTP Response Code: %{http_code}\n' -H 'Host: carmenkalbermatten.ch' https://127.0.0.1/"
$VSSH "crontab -l | grep carmen"

echo "==> SUCCESS: carmenkalbermatten.ch successfully migrated to vps2.agrarix.net!"
