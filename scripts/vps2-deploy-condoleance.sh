#!/bin/bash
# File    : vps2-deploy-condoleance.sh
# Subject : Deploy condolence register to new.biancawennink.nl on vps2
set -euo pipefail

VPS2_HOST="automation@vps2.agrarix.net"
REPO_DIR="/home/automation/proxmox-pve"

echo "==> [1/5] Syncing git repo on fabrix..."
cd "${REPO_DIR}"
git pull origin main || true

echo "==> [2/5] Creating data directory, webroot, and updating DirectoryIndex on vps2..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS2_HOST}" 'bash -s' << 'EOF'
sudo mkdir -p /home/automation/biancawennink-nl/data/condoleances
sudo mkdir -p /home/automation/biancawennink-nl/data/afgekeurd
sudo chown -R automation:www-data /home/automation/biancawennink-nl
sudo find /home/automation/biancawennink-nl/data -type d -exec chmod 2775 {} +
sudo find /home/automation/biancawennink-nl/data -type f -exec chmod 664 {} +
sudo mkdir -p /var/www/vhosts/new.biancawennink.nl/html/condoleanceregister
sudo chown -R automation:www-data /var/www/vhosts/new.biancawennink.nl/html/condoleanceregister

# Ensure DirectoryIndex includes index.php and disable Indexes
for f in /etc/apache2/sites-available/*biancawennink*.conf; do
  if [ -f "$f" ]; then
    sudo sed -i 's/DirectoryIndex index.html index.htm/DirectoryIndex index.php index.html index.htm/' "$f"
    sudo sed -i 's/Options Indexes FollowSymLinks/Options FollowSymLinks/' "$f"
  fi
done
sudo systemctl reload apache2
EOF

echo "==> [3/5] Deploying PHP index.php and updater script to vps2..."
cat "${REPO_DIR}/sites/biancawennink/condoleanceregister/index.php" | \
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS2_HOST}" \
  "cat > /var/www/vhosts/new.biancawennink.nl/html/condoleanceregister/index.php && chmod 664 /var/www/vhosts/new.biancawennink.nl/html/condoleanceregister/index.php"

cat "${REPO_DIR}/scripts/vps-sites/upd_biancawennink.sh" | \
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS2_HOST}" \
  "cat > /home/automation/bin/upd_biancawennink.sh && chmod +x /home/automation/bin/upd_biancawennink.sh"

echo "==> [4/5] Regenerating new.biancawennink.nl homepage with condolence register link..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS2_HOST}" \
  "CUSTOM_WEBDIR=/var/www/vhosts/new.biancawennink.nl/html /home/automation/bin/upd_biancawennink.sh"

echo "==> [5/5] Testing condolence register endpoint..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS2_HOST}" \
  "curl -sI https://new.biancawennink.nl/condoleanceregister/ | head -n 10"

echo "==> Condolence register successfully deployed to https://new.biancawennink.nl/condoleanceregister/"
