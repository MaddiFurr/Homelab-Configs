#!/bin/bash

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

# Function to update firewall rules
update_firewall() {
    local port=$1
    log_message "Attempting to update firewall rules for port $port..."

    if command -v firewall-cmd &> /dev/null; then
        # firewalld detected
        log_message "firewalld detected. Adding port $port/tcp permanently and reloading."
        sudo firewall-cmd --zone=public --add-port=$port/tcp --permanent
        if [ $? -eq 0 ]; then
            sudo firewall-cmd --reload
            log_message "Port $port/tcp added to firewalld and reloaded."
        else
            log_message "Warning: Failed to add port $port/tcp to firewalld. It might already exist or there was an error."
        fi

        # Remove old port if it's the default 22
        if [ "$port" != "$OLD_SSH_PORT" ]; then
            log_message "Removing old SSH port $OLD_SSH_PORT/tcp from firewalld permanently and reloading."
            sudo firewall-cmd --zone=public --remove-port=$OLD_SSH_PORT/tcp --permanent
            if [ $? -eq 0 ]; then
                sudo firewall-cmd --reload
                log_message "Old port $OLD_SSH_PORT/tcp removed from firewalld."
            else
                log_message "Warning: Failed to remove old port $OLD_SSH_PORT/tcp from firewalld (it might not have been open)."
            fi
        fi

    elif command -v ufw &> /dev/null; then
        # ufw detected
        log_message "ufw detected. Allowing port $port/tcp."
        sudo ufw allow $port/tcp
        if [ $? -eq 0 ]; then
            log_message "Port $port/tcp allowed in ufw."
        else
            log_message "Warning: Failed to allow port $port/tcp in ufw. It might already be allowed or there was an error."
        fi

        # Remove old port if it's the default 22
        if [ "$port" != "$OLD_SSH_PORT" ]; then
            log_message "Disabling old SSH port $OLD_SSH_PORT/tcp in ufw."
            sudo ufw delete allow $OLD_SSH_PORT/tcp
            if [ $? -eq 0 ]; then
                log_message "Old port $OLD_SSH_PORT/tcp disabled in ufw."
            else
                log_message "Warning: Failed to disable old port $OLD_SSH_PORT/tcp in ufw (it might not have been open)."
            fi
        fi
    else
        log_message "Warning: Neither firewalld nor ufw found. Please manually open port $port/tcp in your server's firewall before restarting SSH."
    fi
}

# --- Main Script ---

log_message "Starting SSH configuration script with port change."

# 0. Update Firewall First
log_message "Updating firewall to allow new SSH port $NEW_SSH_PORT."
update_firewall "$NEW_SSH_PORT"

# 1. Download the CA Public Key
log_message "Attempting to download CA public key from: $CA_PUB_KEY_URL"
if ! command -v curl &> /dev/null; then
    log_message "curl not found. Installing curl..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y curl
    elif command -v yum &> /dev/null; then
        sudo yum install -y curl
    else
        log_message "Error: Neither apt-get nor yum found. Please install curl manually."
        exit 1
    fi
fi

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

# 2. Configure sshd_config
log_message "Updating $SSHD_CONFIG_FILE for CA authentication, no password login over SSH, and new port."

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

# Change SSH Port
log_message "Changing SSH Port from $OLD_SSH_PORT to $NEW_SSH_PORT in $SSHD_CONFIG_FILE."
if grep -q "^Port" "$SSHD_CONFIG_FILE"; then
    sudo sed -i "s|^#\?\(Port\s*\).*|\1 $NEW_SSH_PORT|" "$SSHD_CONFIG_FILE"
else
    echo "Port $NEW_SSH_PORT" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
fi

# 3. Restart SSH Service
log_message "Restarting SSH service to apply changes."
if command -v systemctl &> /dev/null; then
    sudo systemctl restart sshd
elif command -v service &> /dev/null; then
    sudo service sshd restart
else
    log_message "Warning: Could not find systemctl or service command. Please restart SSH service manually."
fi

log_message "SSH configuration script finished. SSH port is now $NEW_SSH_PORT."
log_message "Password login over SSH is disabled, but console login should still work."
log_message "You should now be able to log in using SSH certificates or individual public keys on port $NEW_SSH_PORT."
log_message "Remember to connect using 'ssh -p $NEW_SSH_PORT user@server_ip' from now on."
