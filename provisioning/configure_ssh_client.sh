#!/bin/bash
set -euo pipefail


CA_URL="https://ca.infra.puppygirl.io"

CA_FINGERPRINT="d5388874d90a3a541d234c7e1759e16b3177203944ef6ab1a59a04670c1bce0a"

OIDC_PROVISIONER_NAME="keycloak-ssh"

OIDC_CALLBACK_URL="http://127.0.0.1:10000"

echo "--- Starting Smallstep CLI Setup for SSH Certificates ---"

# 1. Install step-cli
echo "1. Installing Smallstep CLI..."
if ! command -v step &> /dev/null
then
    echo "Downloading and installing step-cli. This requires internet access."
    curl -sL https://install.smallstep.com/step-cli | bash
    # Attempt to add to PATH for current session (usually done by the installer too)
    export PATH="$HOME/.local/bin:$PATH"
    echo "step-cli installed. You may need to open a new terminal for PATH changes to take full effect."
else
    echo "step-cli is already installed."
fi

# Ensure step-cli is available in PATH for subsequent commands
if ! command -v step &> /dev/null; then
    echo "ERROR: step-cli is not found in PATH after installation. Please ensure $HOME/.local/bin is in your PATH."
    echo "You might need to manually add it or open a new terminal and try again."
    exit 1
fi


# 2. Configure step-cli defaults.json
echo "2. Configuring ~/.step/config/defaults.json..."
mkdir -p ~/.step/config

cat <<EOF > ~/.step/config/defaults.json
{
  "ca-url": "$CA_URL",
  "fingerprint": "$CA_FINGERPRINT",
  "tls": {
    "rootCAs": ["system"]
  },
  "provisioner": "$OIDC_PROVISIONER_NAME"
}
EOF
echo "defaults.json created."


# 3. Bootstrap CA root certificate (requires sudo for system trust store)
echo "3. Bootstrapping CA root certificate (requires sudo for system trust store)..."
echo "Retrieving CA root certificate from $CA_URL/roots.pem..."
step_ca_root_path="$HOME/.step/certs/root_ca.crt"
mkdir -p ~/.step/certs # Ensure ~/.step/certs exists

# Download the root cert directly from the CA's /roots.pem endpoint
if curl -s "$CA_URL/roots.pem" > "$step_ca_root_path"; then
    echo "CA root certificate saved to $step_ca_root_path"
else
    echo "ERROR: Failed to download CA root certificate from $CA_URL/roots.pem"
    echo "Please ensure the CA is running and accessible from your current machine via Tailscale."
    exit 1
fi

# Install the root certificate to the system trust store
# This requires sudo.
if sudo step certificate install "$step_ca_root_path" --all; then
    echo "CA root certificate installed to system trust store. This ensures TLS connections work."
else
    echo "WARNING: Failed to install CA root certificate to system trust store. Manual installation may be required."
    echo "See: https://smallstep.com/docs/step-cli/reference/certificate/install"
fi


# 4. Create a convenient 'getssh' alias as a shell function
echo "4. Creating 'getssh' alias function..."
SHELL_RC_FILE=""
if [[ "$SHELL" == *bash* ]]; then
    SHELL_RC_FILE="$HOME/.bashrc"
elif [[ "$SHELL" == *zsh* ]]; then
    SHELL_RC_FILE="$HOME/.zshrc"
else
    echo "WARNING: Could not determine shell RC file (.bashrc or .zshrc). Please add the alias manually."
fi

# Define the getssh function
GETSSH_FUNCTION=$(cat <<'EOF_FUNC'
# Function to get SSH certificate from Smallstep CA
# Defaults to current system username if no argument is provided.
getssh() {
  local username="$1"
  if [ -z "$username" ]; then
    username=$(whoami) # Use current system username if none provided
    echo "No username provided. Defaulting to system user: $username"
  fi
  # Use the OIDC_CALLBACK_URL from the setup script's config.
  # This makes the alias robust even if the script's original scope ends.
  local callback_url="http://127.0.0.1:10000" # Hardcode or pass from environment

  echo "Attempting to get SSH certificate for user: $username"
  echo "This will open a browser for Keycloak login. Please complete the login."
  step ssh login --listen-address "$callback_url" "$username"
  echo "Certificate retrieval command completed."
}
EOF_FUNC
)

# Add the function to the shell RC file if it doesn't exist
if [ -n "$SHELL_RC_FILE" ]; then
    if ! grep -q "function getssh" "$SHELL_RC_FILE"; then
        echo "$GETSSH_FUNCTION" >> "$SHELL_RC_FILE"
        echo "Function 'getssh' added to $SHELL_RC_FILE."
        echo "Please run 'source $SHELL_RC_FILE' or open a new terminal window to use it."
    else
        echo "Function 'getssh' already exists in $SHELL_RC_FILE."
    fi
else
    echo "Could not add 'getssh' function automatically. Please add it manually to your shell config file."
fi


echo ""
echo "--- Smallstep CLI Setup Complete! ---"
echo ""
echo "------------------------------------------------------------------------------------------------"
echo "  NEXT STEPS FOR THE USER:"
echo "------------------------------------------------------------------------------------------------"
echo "1. Open a NEW TERMINAL WINDOW (or run 'source ~/.bashrc' or 'source ~/.zshrc')."
echo "2. To get your SSH certificate for user '$USER':"
echo "      getssh"
echo "   (This will open a browser for Keycloak login. Complete the login, then return to terminal.)"
echo "3. To get your SSH certificate for a different user (e.g., 'alice'):"
echo "      getssh alice"
echo "4. Once you have a certificate in your SSH agent, you can SSH into configured servers:"
echo "      ssh <your_username_on_vps>@<vps_ip_or_hostname>"
echo "------------------------------------------------------------------------------------------------"
