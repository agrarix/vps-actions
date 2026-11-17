#!/bin/bash
# File    : vps2-test-moderation.sh
# Subject : Test condolence approval and rejection on new.biancawennink.nl
set -euo pipefail

VPS2_HOST="automation@vps2.agrarix.net"

ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${VPS2_HOST}" 'bash -s' << 'EOF'
set -euo pipefail

SECRET=$(cat /home/automation/biancawennink-nl/data/.moderation_secret)
PENDING_FILE=$(ls -t /home/automation/biancawennink-nl/data/condoleances/*.txt | head -1)
FILE_ID=$(basename "${PENDING_FILE}" .txt)

echo "Testing message: ${FILE_ID}"
echo "Current status:"
grep "^STATUS:" "${PENDING_FILE}"

# Test 1: Goedkeuren
TOKEN_APPROVE=$(php -r "echo hash_hmac('sha256', '${FILE_ID}:approve', '${SECRET}');")
echo "Approve token: ${TOKEN_APPROVE}"
curl -sL "https://new.biancawennink.nl/condoleanceregister/?actie=approve&file=${FILE_ID}&token=${TOKEN_APPROVE}" > /dev/null
echo "Status after approve:"
grep "^STATUS:" "${PENDING_FILE}"

# Test 2: Afkeuren & verplaatsen naar data/afgekeurd/
TOKEN_REJECT=$(php -r "echo hash_hmac('sha256', '${FILE_ID}:reject', '${SECRET}');")
echo "Reject token: ${TOKEN_REJECT}"
curl -sL "https://new.biancawennink.nl/condoleanceregister/?actie=reject&file=${FILE_ID}&token=${TOKEN_REJECT}" > /dev/null

echo "Check data/condoleances/:"
if [ -f "/home/automation/biancawennink-nl/data/condoleances/${FILE_ID}.txt" ]; then
  echo "FAIL: File still in condoleances/"
else
  echo "SUCCESS: File removed from condoleances/"
fi

echo "Check data/afgekeurd/:"
if [ -f "/home/automation/biancawennink-nl/data/afgekeurd/${FILE_ID}.txt" ]; then
  echo "SUCCESS: File moved to data/afgekeurd/"
  cat "/home/automation/biancawennink-nl/data/afgekeurd/${FILE_ID}.txt"
else
  echo "FAIL: File not found in data/afgekeurd/"
fi
EOF
