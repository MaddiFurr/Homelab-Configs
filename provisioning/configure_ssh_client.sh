#!/bin/bash

# Script to configure a new SSH target server to trust Vault-issued SSH certificates.
# This script should be run with root/sudo privileges.

# Configuration Variables
GITHUB_USER="MaddiFurr"
GITHUB_REPO="Homelab-Configs"
GITHUB_VAULT_SSH_CA_PATH="tree/main/provisioning/keys/vault_ssh_ca.pub"

# Derived Variables
GITHUB_RAW_URL_VAULT_CA="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/${GITHUB_VAULT_SSH_CA_CA_PATH}"
TRUSTED_KEYS_DIR="/etc/ssh/trusted_user_ca_keys.d"
CA_PUB_FILE="vault_ssh_ca.pub"
SSHD_CONFIG="/etc/ssh/sshd_config"

message() {
    echo "$1"
}

error_exit() {
    echo "FAILURE: $1" >&2
    exit 1
}

if [[ "$EUID" -ne 0 ]]; then
    error_exit "This script must be run with sudo or as root."
fi

message "Starting SSH certificate configuration for Vault..."

message "  - Checking for curl installation..."
if ! command -v curl &> /dev/null; then
    message "    curl not found. Attempting to install..."
    if command -v apt &> /dev/null; then
        apt update -y || error_exit "Failed to update apt packages."
        apt install -y curl || error_exit "Failed to install curl."
    elif command -v dnf &> /dev/null; then
        dnf install -y curl || error_exit "Failed to install curl."
    elif command -v yum &> /dev/null; then
        yum install -y curl || error_exit "Failed to install curl."
    else
        error_exit "No suitable package manager (apt, dnf, yum) found to install curl. Please install manually."
    fi
    message "    curl installed successfully."
else
    message "    curl is already installed."
fi

message "  - Creating directory ${TRUSTED_KEYS_DIR}..."
mkdir -p "${TRUSTED_KEYS_DIR}" || error_exit "Failed to create directory ${TRUSTED_KEYS_DIR}."
message "    Directory created."

message "  - Downloading Vault SSH CA public key..."
if ! curl -sL "${GITHUB_RAW_URL_VAULT_CA}" -o "${TRUSTED_KEYS_DIR}/${CA_PUB_FILE}"; then
    error_exit "Failed to download Vault SSH CA public key from GitHub. Check GITHUB_USER, GITHUB_REPO, GITHUB_VAULT_SSH_CA_PATH in script, and internet connectivity."
fi
message "    Vault SSH CA public key downloaded."

message "  - Setting permissions for ${CA_PUB_FILE}..."
chmod 644 "${TRUSTED_KEYS_DIR}/${CA_PUB_FILE}" || error_exit "Failed to set permissions for ${CA_PUB_FILE}."
message "    Permissions set to 644."

message "  - Configuring sshd_config..."
if ! grep -q "^TrustedUserCAKeys" "${SSHD_CONFIG}"; then
    echo "TrustedUserCAKeys ${TRUSTED_KEYS_DIR}/" | tee -a "${SSHD_CONFIG}" || error_exit "Failed to append TrustedUserCAKeys to sshd_config."
    message "    Added TrustedUserCAKeys directive."
else
    sed -i "s|^TrustedUserCAKeys.*|TrustedUserCAKeys ${TRUSTED_KEYS_DIR}/|" "${SSHD_CONFIG}" || error_exit "Failed to update TrustedUserCAKeys in sshd_config."
    message "    Updated TrustedUserCAKeys directive."
fi

if grep -q "^#\?PubkeyAuthentication no" "${SSHD_CONFIG}"; then
    sed -i "s|^#\?PubkeyAuthentication no|PubkeyAuthentication yes|" "${SSHD_CONFIG}" || error_exit "Failed to enable PubkeyAuthentication."
    message "    Ensured PubkeyAuthentication is set to 'yes'."
elif ! grep -q "^PubkeyAuthentication yes" "${SSHD_CONFIG}"; then
    echo "PubkeyAuthentication yes" | tee -a "${SSHD_CONFIG}" || error_exit "Failed to ensure PubkeyAuthentication is enabled."
    message "    Added PubkeyAuthentication 'yes' directive."
else
    message "    PubkeyAuthentication is already enabled."
fi

message "  - Restarting sshd service..."
systemctl restart sshd || error_exit "Failed to restart sshd service. Check systemd logs (journalctl -xeu sshd)."
message "    sshd service restarted successfully."

echo ""
echo "SUCCESS: SSH certificate configuration complete for Vault. You should now be able to SSH using Vault-issued certificates."