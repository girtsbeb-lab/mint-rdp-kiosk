#!/bin/bash
# install-semaphore.sh
# Installs Docker + Docker Compose and starts Semaphore UI on the
# control server, pointed at the mint-rdp-kiosk playbook.
set -euo pipefail

SEMAPHORE_DIR="${SEMAPHORE_DIR:-/opt/semaphore}"
PROJECT_DIR="${PROJECT_DIR:-/opt/mint-rdp-kiosk}"

if [ ! -d "${PROJECT_DIR}" ]; then
  echo "ERROR: ${PROJECT_DIR} not found."
  echo "Copy the mint-rdp-kiosk playbook there first (see setup-control-node.sh)."
  exit 1
fi

echo "==> Installing Docker (if not already present)"
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$(whoami)"
  echo "    Docker installed. You may need to log out/in for group membership to apply."
else
  echo "    Docker already installed."
fi

echo "==> Setting up ${SEMAPHORE_DIR}"
sudo mkdir -p "${SEMAPHORE_DIR}"
sudo chown "$(whoami)" "${SEMAPHORE_DIR}"
cp docker-compose.yml "${SEMAPHORE_DIR}/"

echo "==> Generating admin password + encryption key"
ADMIN_PASS="$(head -c16 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c16)"
ENC_KEY="$(head -c32 /dev/urandom | base64)"

sed -i "s#CHANGE_ME_TOO#${ENC_KEY}#" "${SEMAPHORE_DIR}/docker-compose.yml"
sed -i "s#SEMAPHORE_ADMIN_PASSWORD: \"CHANGE_ME\"#SEMAPHORE_ADMIN_PASSWORD: \"${ADMIN_PASS}\"#" "${SEMAPHORE_DIR}/docker-compose.yml"

echo "==> Starting Semaphore"
cd "${SEMAPHORE_DIR}"
docker compose up -d

echo
echo "======================================================"
echo " Semaphore UI is starting up."
echo "   URL:      http://$(hostname -I | awk '{print $1}'):3000"
echo "   Username: admin"
echo "   Password: ${ADMIN_PASS}"
echo
echo " (also saved in ${SEMAPHORE_DIR}/docker-compose.yml"
echo "  under SEMAPHORE_ADMIN_PASSWORD -- change it after first login)"
echo "======================================================"
echo
echo "Next: log in, then follow the 'Configuring Semaphore' steps in"
echo "README.md to point it at the mint-rdp-kiosk playbook."
