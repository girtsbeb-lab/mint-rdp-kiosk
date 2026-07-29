#!/bin/bash
# setup-control-node.sh
# Run this ONCE on the dedicated Ubuntu server that will manage the
# Mint kiosk fleet. Installs Ansible, generates the SSH key this server
# will use to reach every kiosk, and lays out the project directory.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/mint-rdp-kiosk}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/root/.ssh/mint_kiosk_admin}"

echo "==> Installing Ansible + SSH tooling"
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible openssh-client sshpass

echo "==> Ansible version:"
ansible --version | head -n1

echo "==> Generating dedicated SSH key for kiosk management (if not present)"
if [ ! -f "${SSH_KEY_PATH}" ]; then
  ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -N "" -C "ansible-control@$(hostname)"
  echo "    Created ${SSH_KEY_PATH}"
else
  echo "    ${SSH_KEY_PATH} already exists, leaving it alone"
fi

echo "==> Project directory: ${PROJECT_DIR}"
sudo mkdir -p "${PROJECT_DIR}"
sudo chown "$(whoami)" "${PROJECT_DIR}"

echo
echo "Next steps:"
echo "1. Copy the playbook files (site.yml, inventory.ini, ansible.cfg,"
echo "   group_vars/) into: ${PROJECT_DIR}"
echo "2. Put this server's public key into group_vars/all.yml as"
echo "   admin_ssh_pubkey:"
echo "     $(cat "${SSH_KEY_PATH}.pub")"
echo "3. For EACH kiosk, copy this key to the manually-created bootstrap"
echo "   account (the one referenced as ansible_user in inventory.ini),"
echo "   so this server can reach it for the very first run:"
echo "     ssh-copy-id -i ${SSH_KEY_PATH}.pub <ansible_user>@<kiosk-ip>"
echo "4. Point ssh at the right key, e.g. in ~/.ssh/config on this server:"
echo "     Host mint-term-*"
echo "       IdentityFile ${SSH_KEY_PATH}"
echo "5. Run the playbook:"
echo "     cd ${PROJECT_DIR} && ansible-playbook site.yml"
echo
echo "After the first successful run, every kiosk trusts this same key"
echo "under the dedicated 'admin' account, so future runs and ad-hoc"
echo "'ssh admin@mint-term-01' commands work without any extra setup."
