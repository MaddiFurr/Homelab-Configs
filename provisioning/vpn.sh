#!/bin/bash

# Configuration
HEADSCALE_URL="https://vpn.puppygirl.io"
HEADPLANE_KEY_GEN_URL="https://management-vpn.puppygirl.io/admin/settings/auth-keys"
TAILSCALE_STATE_DIR="/var/lib/tailscale"

# --- Functions ---

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

install_tailscale() {
  log_message "Tailscale not found. Installing..."
  curl -fsSL https://tailscale.com/install.sh | sudo bash

  if [ $? -ne 0 ]; then
    log_message "Error installing Tailscale. Exiting."
    exit 1
  fi
  log_message "Tailscale installed successfully."
}

# --- Main Script Logic ---

log_message "Starting Headscale auto-login script."

PREAUTH_KEY="$1"

# 1. Check if Tailscale is installed, install if not
if ! command -v tailscale &> /dev/null; then
  install_tailscale
fi

# 2. Check if Tailscale is already configured/logged in
if [ -s "$TAILSCALE_STATE_DIR/tailscaled.state" ]; then
  log_message "Tailscale appears to be already configured. Checking status."
  STATUS=$(sudo tailscale status --json 2>/dev/null)
  if echo "$STATUS" | grep -q '"Self"'; then
    PEER_COUNT=$(echo "$STATUS" | jq '.Peer | length' 2>/dev/null)
    if [ "$PEER_COUNT" -gt 0 ]; then
      log_message "Tailscale is already connected to a tailnet with peers. Enabling service for boot and exiting."
      sudo systemctl enable tailscaled
      sudo systemctl start tailscaled
      exit 0
    else
      log_message "Tailscale is configured but might not be connected to a tailnet or has no peers. Proceeding to login."
    fi
  fi
fi

# 3. If no key provided, prompt user and provide link
if [ -z "$PREAUTH_KEY" ]; then
  log_message "No pre-auth key provided. Please generate one and paste it below."
  log_message "--------------------------------------------------------------------------"
  log_message "Click this link to generate a pre-auth key in Headplane (requires login):"
  log_message "--> $HEADPLANE_KEY_GEN_URL"
  log_message "--------------------------------------------------------------------------"
  log_message "In Headplane, select the 'infrastructure' user, choose 'Reusable' and 'Ephemeral',"
  log_message "set an expiration, then click 'Generate' and copy the key."
  read -p "Paste the generated pre-auth key here: " PREAUTH_KEY < /dev/tty
  echo
fi

# Validate the entered key (basic check)
if [[ ! "$PREAUTH_KEY" =~ ^hu_[a-zA-Z0-9]{64,}$ ]]; then
    log_message "Invalid pre-auth key format. It should start with 'hu_' and be a long alphanumeric string. Exiting."
    exit 1
fi

# 4. Attempt to log in using the pre-auth key
log_message "Attempting to login to Headscale using pre-auth key."
sudo tailscale up --login-server="$HEADSCALE_URL" --authkey="$PREAUTH_KEY" --force-reauth=false --reset=false --ssh --advertise-routes=auto

if [ $? -eq 0 ]; then
  log_message "Successfully logged in to Headscale."
  # 5. Enable and start tailscaled service on boot
  log_message "Enabling tailscaled service to start on boot."
  sudo systemctl enable tailscaled
  sudo systemctl start tailscaled

  if [ $? -ne 0 ]; then
    log_message "Warning: Failed to enable/start tailscaled service on boot. Manual intervention may be needed."
  else
    log_message "Tailscale service enabled for boot and started."
  fi

else
  log_message "Failed to log in to Headscale. Check logs and configuration."
  exit 1
fi

log_message "Script finished."