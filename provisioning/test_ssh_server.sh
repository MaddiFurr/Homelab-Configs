#!/bin/bash

# --- Configuration ---
# URL where the CA public key is located.
CA_PUB_KEY_URL="https://raw.githubusercontent.com/MaddiFurr/Homelab-Configs/refs/heads/main/provisioning/keys/ssh_user_ca_key.pub"

# Path for the trusted CA keys file on the server
TRUSTED_CA_KEYS_FILE="/etc/ssh/trusted-user-ca-keys.pem"

# SSHD configuration file path
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"

# New SSH Port
NEW_SSH_PORT="42069"
OLD_SSH_PORT="22" # Default SSH port

# --- Functions ---

log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Function to update firewall rules - Adjusted for LXC
# NOTE: Firewalls like firewalld/ufw are usually run on the LXC *host*, not inside the container.
# This function will likely not perform any action and is included as a reminder.
# You MUST configure your LXC host's firewall to allow traffic to the container's IP on $NEW_SSH_PORT.
update_firewall() {
    local port=$1
    log_message "Attempting to update firewall rules for port $port... (Note: This typically applies to the LXC host, not within the container.)"

    if command -v firewall-cmd &> /dev/null; then
        log_message "firewalld detected inside container. Skipping firewall rule update as it's typically controlled by LXC host."
        # If for some reason you run firewalld inside a container and want to manage it, uncomment:
        # sudo firewall-cmd --zone=public --add-port=$port/tcp --permanent
        # sudo firewall-cmd --reload
        # if [ "$port" != "$OLD_SSH_PORT" ]; then
        #     sudo firewall-cmd --zone=public --remove-port=$OLD_SSH_PORT/tcp --permanent
        #     sudo firewall-cmd --reload
        # fi
    elif command -v ufw &> /dev/null; then
        log_message "ufw detected inside container. Skipping firewall rule update as it's typically controlled by LXC host."
        # If for some reason you run ufw inside a container and want to manage it, uncomment:
        # sudo ufw allow $port/tcp
        # if [ "$port" != "$OLD_SSH_PORT" ]; then
        #     sudo ufw delete allow $OLD_SSH_PORT/tcp
        # fi
    else
        log_message "No common firewall manager (firewalld/ufw) found inside container. Remember to open port $port/tcp on your LXC host's firewall!"
    fi
}

# --- Main Script ---

log_message "Starting SSH configuration script for LXC container."

# 0. Update Firewall First (Note: This is mostly a placeholder for LXC, host firewall is key)
log_message "Attempting to update container's firewall (if any) to allow new SSH port $NEW_SSH_PORT."
update_firewall "$NEW_SSH_PORT"

# 1. Install curl if not present (often needed in minimal container images)
log_message "Ensuring curl is installed for downloading CA key."
if ! command -v curl &> /dev/null; then
    log_message "curl not found. Installing curl..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y curl
    elif command -v yum &> /dev/null; then
        sudo yum install -y curl
    elif command -v dnf &> /dev/null; then # Add dnf for newer Fedora/RHEL
        sudo dnf install -y curl
    else
        log_message "Error: Neither apt-get, yum, nor dnf found. Please install curl manually."
        exit 1
    fi
fi

# 2. Download the CA Public Key
log_message "Attempting to download CA public key from: $CA_PUB_KEY_URL"
sudo curl -sfL "$CA_PUB_KEY_URL" -o "$TRUSTED_CA_KEYS_FILE"
if [ $? -ne 0 ]; then
    log_message "Error: Failed to download CA public key. Exiting."
    exit 1
fi
log_message "CA public key downloaded and saved to $TRUSTED_CA_KEYS_FILE"

# Set correct permissions
sudo chmod 644 "$TRUSTED_CA_KEYS_FILE"
sudo chown root:root "$TRUSTED_CA_KEYS_FILE"
log_message "Permissions set for $TRUSTED_CA_KEYS_FILE"

# 3. Configure sshd_config
log_message "Updating $SSHD_CONFIG_FILE for CA authentication, no password login over SSH, new port, and root login."

# Add or update TrustedUserCAKeys directive
if ! grep -q "^TrustedUserCAKeys" "$SSHD_CONFIG_FILE"; then
    log_message "Adding TrustedUserCAKeys directive."
    echo "TrustedUserCAKeys $TRUSTED_CA_KEYS_FILE" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
else
    log_message "TrustedUserCAKeys directive already exists. Ensuring it points to the correct file."
    sudo sed -i "s|^#\?\(TrustedUserCAKeys\s*\).*|\1 $TRUSTED_CA_KEYS_FILE|" "$SSHD_CONFIG_FILE"
fi

# Set PasswordAuthentication to no (for SSH logins only)
log_message "Setting PasswordAuthentication to no in $SSHD_CONFIG_FILE to disable password login over SSH."
if grep -q "^PasswordAuthentication" "$SSHD_CONFIG_FILE"; then
    sudo sed -i "s|^#\?\(PasswordAuthentication\s*\).*|\1 no|" "$SSHD_CONFIG_FILE"
else
    echo "PasswordAuthentication no" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
fi

# Ensure PubkeyAuthentication is 'yes' (needed for certs and regular public keys)
log_message "Ensuring PubkeyAuthentication is set to yes."
if grep -q "^PubkeyAuthentication" "$SSHD_CONFIG_FILE"; then
    sudo sed -i "s|^#\?\(PubkeyAuthentication\s*\).*|\1 yes|" "$SSHD_CONFIG_FILE"
else
    echo "PubkeyAuthentication yes" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
fi

# Disable ChallengeResponseAuthentication (good practice unless specifically needed)
log_message "Ensuring ChallengeResponseAuthentication is off."
if grep -q "^ChallengeResponseAuthentication" "$SSHD_CONFIG_FILE"; then
    sudo sed -i "s|^#\?\(ChallengeResponseAuthentication\s*\).*|\1 no|" "$SSHD_CONFIG_FILE"
else
    echo "ChallengeResponseAuthentication no" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
fi

# Explicitly Allow Root SSH Login (for testing only!)
log_message "Setting PermitRootLogin to 'yes' (for testing purposes)."
if grep -q "^PermitRootLogin" "$SSHD_CONFIG_FILE"; then
    sudo sed -i "s|^#\?\(PermitRootLogin\s*\).*|\1 yes|" "$SSHD_CONFIG_FILE"
else
    echo "PermitRootLogin yes" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
fi


# Change SSH Port
log_message "Changing SSH Port from $OLD_SSH_PORT to $NEW_SSH_PORT in $SSHD_CONFIG_FILE."
if grep -q "^Port" "$SSHD_CONFIG_FILE"; then
    sudo sed -i "s|^#\?\(Port\s*\).*|\1 $NEW_SSH_PORT|" "$SSHD_CONFIG_FILE"
else
    echo "Port $NEW_SSH_PORT" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
fi

# 4. Restart SSH Service
log_message "Restarting SSH service to apply changes."
if command -v systemctl &> /dev/null; then
    sudo systemctl restart sshd
elif command -v service &> /dev/null; then
    sudo service sshd restart
else
    log_message "Warning: Could not find systemctl or service command. Please restart SSH service manually."
fi

log_message "SSH configuration script finished for LXC container. SSH port is now $NEW_SSH_PORT."
log_message "Password login over SSH is disabled, but console login should still work."
log_message "Root SSH login is ENABLED for testing. Remember to disable this for production!"
log_message "You should now be able to log in using SSH certificates or individual public keys on port $NEW_SSH_PORT."
log_message "Remember to connect using 'ssh -p $NEW_SSH_PORT user@container_ip' from now on."
log_message "IMPORTANT: Ensure your LXC HOST's firewall is configured to allow traffic to this container on port $NEW_SSH_PORT."
