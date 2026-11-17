#!/bin/bash
# scripts/vps2-setup-new-bianca.sh
# Create new.biancawennink.nl on vps2.agrarix.net (212.227.209.36) as copy of biancawennink.nl
# Run on fabrix (automation@192.168.178.40)
set -e

VPS="automation@vps2.agrarix.net"
VSSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $VPS"
SRC_DIR="/var/www/vhosts/biancawennink.nl/html"
DST_DIR="/var/www/vhosts/new.biancawennink.nl/html"

echo "==> [1/5] Copy docroot on vps2"
$VSSH "sudo mkdir -p /var/www/vhosts/new.biancawennink.nl"
$VSSH "sudo cp -a $SRC_DIR /var/www/vhosts/new.biancawennink.nl/"
$VSSH "sudo chown -R automation:automation /var/www/vhosts/new.biancawennink.nl"
$VSSH "sudo chmod 755 /var/www/vhosts/new.biancawennink.nl $DST_DIR"

echo "==> [2/5] Create Apache HTTP VirtualHost"
cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/new.biancawennink.nl.conf > /dev/null"
<VirtualHost *:80>
    ServerAdmin webadmin@agrarix.net
    ServerName new.biancawennink.nl
    ServerAlias new.biancawennink.nl
    DocumentRoot /var/www/vhosts/new.biancawennink.nl/html

    <Directory /var/www/vhosts/new.biancawennink.nl/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        DirectoryIndex index.html index.htm default.htm default.html
    </Directory>

    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^/?(.*) https://%{HTTP_HOST}/$1 [R=301,L]

    ErrorLog ${APACHE_LOG_DIR}/new.biancawennink.nl_error.log
    CustomLog ${APACHE_LOG_DIR}/new.biancawennink.nl_access.log combined
</VirtualHost>
EOF

$VSSH "sudo a2ensite new.biancawennink.nl.conf && sudo apache2ctl configtest && sudo systemctl reload apache2"

echo "==> [3/5] Request Let's Encrypt Certificate"
$VSSH "sudo certbot certonly --webroot -w $DST_DIR -d new.biancawennink.nl --non-interactive --agree-tos -m webadmin@agrarix.net"

# Update renewal config to use apache
$VSSH "sudo sed -i -e 's/^authenticator = .*/authenticator = apache/' -e 's/^installer = .*/installer = apache/' /etc/letsencrypt/renewal/new.biancawennink.nl.conf 2>/dev/null || true"
$VSSH "sudo grep -q '^installer = ' /etc/letsencrypt/renewal/new.biancawennink.nl.conf 2>/dev/null || sudo sed -i '/^authenticator = apache/a installer = apache' /etc/letsencrypt/renewal/new.biancawennink.nl.conf 2>/dev/null || true"

echo "==> [4/5] Create Apache HTTPS VirtualHost"
cat << 'EOF' | $VSSH "sudo tee /etc/apache2/sites-available/new.biancawennink.nl-le-ssl.conf > /dev/null"
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerAdmin webadmin@agrarix.net
    ServerName new.biancawennink.nl
    ServerAlias new.biancawennink.nl
    DocumentRoot /var/www/vhosts/new.biancawennink.nl/html

    <Directory /var/www/vhosts/new.biancawennink.nl/html>
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

    SSLCertificateFile /etc/letsencrypt/live/new.biancawennink.nl/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/new.biancawennink.nl/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ErrorLog ${APACHE_LOG_DIR}/new.biancawennink.nl_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/new.biancawennink.nl_ssl_access.log combined
</VirtualHost>
</IfModule>
EOF

$VSSH "sudo a2ensite new.biancawennink.nl-le-ssl.conf && sudo apache2ctl configtest && sudo systemctl reload apache2"

echo "==> [5/5] Verify new.biancawennink.nl"
$VSSH "curl -k -s -I -H 'Host: new.biancawennink.nl' https://127.0.0.1/ | head -5"
$VSSH "curl -s -I -H 'Host: new.biancawennink.nl' http://127.0.0.1/ | head -5"
$VSSH "grep -i 'generator' $DST_DIR/index.html"
echo "==> SUCCESS: new.biancawennink.nl is live on vps2!"
