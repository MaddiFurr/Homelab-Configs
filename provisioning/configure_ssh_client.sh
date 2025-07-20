#!/bin/bash

# PuppyGirl Vault SSH Certificate Installation Script
# This script adds the get_vault_ssh_cert function and related aliases to your shell configuration
# It also installs the Vault CLI if not already present

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect shell and configuration file
detect_shell() {
    local shell_name=$(basename "$SHELL")
    case "$shell_name" in
        bash)
            echo "$HOME/.bashrc"
            ;;
        zsh)
            echo "$HOME/.zshrc"
            ;;
        *)
            print_error "Unsupported shell: $shell_name"
            print_error "This script supports bash and zsh only."
            exit 1
            ;;
    esac
}

# Install Vault CLI if not present
install_vault_cli() {
    if command -v vault &> /dev/null; then
        print_status "Vault CLI is already installed ($(vault version))"
        return 0
    fi
    
    print_status "Installing Vault CLI..."
    
    # Detect OS and architecture
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    local vault_version="1.15.2"  # You can update this to the latest version
    local vault_url="https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_${os}_${arch}.zip"
    
    print_status "Downloading Vault CLI from: $vault_url"
    
    # Download and install
    if ! curl -sL "$vault_url" -o "$temp_dir/vault.zip"; then
        print_error "Failed to download Vault CLI"
        rm -rf "$temp_dir"
        return 1
    fi
    
    if ! command -v unzip &> /dev/null; then
        print_error "unzip command not found. Please install unzip and try again."
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd "$temp_dir"
    unzip -q vault.zip
    
    # Install to /usr/local/bin (requires sudo) or ~/.local/bin
    if [ -w "/usr/local/bin" ] || sudo -n true 2>/dev/null; then
        print_status "Installing Vault CLI to /usr/local/bin (requires sudo)"
        sudo mv vault /usr/local/bin/
        sudo chmod +x /usr/local/bin/vault
    else
        print_status "Installing Vault CLI to ~/.local/bin"
        mkdir -p ~/.local/bin
        mv vault ~/.local/bin/
        chmod +x ~/.local/bin/vault
        
        # Add ~/.local/bin to PATH if not already there
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            print_status "Adding ~/.local/bin to PATH in shell configuration"
            local config_file=$(detect_shell)
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$config_file"
        fi
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    print_status "Vault CLI installed successfully"
    return 0
}

# Check if the functions/aliases already exist
check_existing_installation() {
    local config_file="$1"
    
    if [ -f "$config_file" ] && grep -q "get_vault_ssh_cert" "$config_file"; then
        print_warning "get_vault_ssh_cert function already exists in $config_file"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled."
            exit 0
        fi
        return 1
    fi
    return 0
}

# Remove existing installation if it exists
remove_existing_installation() {
    local config_file="$1"
    local temp_file=$(mktemp)
    
    # Remove the existing function and aliases
    awk '
        /^### PUPPYGIRL VAULT SSH SETUP START ###/ { skip = 1; next }
        /^### PUPPYGIRL VAULT SSH SETUP END ###/ { skip = 0; next }
        !skip { print }
    ' "$config_file" > "$temp_file"
    
    mv "$temp_file" "$config_file"
    print_status "Removed existing installation."
}

# Add the function and aliases to the configuration file
add_to_config() {
    local config_file="$1"
    
    cat >> "$config_file" << 'EOF'

### PUPPYGIRL VAULT SSH SETUP START ###

# PuppyGirl Vault SSH Certificate Function
get_vault_ssh_cert() {
  # --- Configuration ---
  local GITHUB_USER="MaddiFurr"
  local GITHUB_REPO="Homelab-Configs"
  local GITHUB_VAULT_CRT_PATH="main/provisioning/keys/vault.crt"

  local VAULT_SERVER_ADDRESS="https://vault.idm.puppygirl.io:8200"
  local VAULT_CA_CERT_PATH="${HOME}/vault.crt"

  local FREEIPA_USERNAME="$1"
  local SSH_CERT_PATH="${HOME}/.ssh/puppygirl_ssh_key-cert.pub"
  local VAULT_SSH_ROLE="freeipa-user-cert"

  # If no argument provided, default to the current local user's username
  if [ -z "${FREEIPA_USERNAME}" ]; then
    FREEIPA_USERNAME=$(whoami)
  fi

  # --- Automatic vault.crt download ---
  if [ ! -f "${VAULT_CA_CERT_PATH}" ]; then
    local RAW_URL_VAULT_CRT="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/${GITHUB_VAULT_CRT_PATH}"
    echo "Vault CA certificate not found at '${VAULT_CA_CERT_PATH}'. Attempting to download from GitHub..."

    # Ensure curl is installed (basic check, could be more robust)
    if ! command -v curl &> /dev/null; then
      echo "ERROR: 'curl' not found. Please install curl to enable automatic certificate download." >&2
      return 1
    fi

    if ! curl -sL "${RAW_URL_VAULT_CRT}" -o "${VAULT_CA_CERT_PATH}"; then
      echo "FAILURE: Failed to download Vault CA certificate from GitHub. Check GITHUB_USER, GITHUB_REPO, GITHUB_VAULT_CRT_PATH, and internet connectivity." >&2
      return 1
    fi
    chmod 644 "${VAULT_CA_CERT_PATH}" # Ensure it's readable
    echo "Vault CA certificate downloaded successfully to '${VAULT_CA_CERT_PATH}'."
  fi

  # --- Core Logic ---
  echo "Attempting Vault login for '${FREEIPA_USERNAME}'..."
  if ! vault login -address="${VAULT_SERVER_ADDRESS}" -ca-cert="${VAULT_CA_CERT_PATH}" -method=oidc; then
    echo "FAILURE: Vault login failed. Run 'vault login -address=\"${VAULT_SERVER_ADDRESS}\" -ca-cert=\"${VAULT_CA_CERT_PATH}\" -method=oidc' manually in a browser and try again." >&2
    return 1
  fi
  echo "Vault login successful."

  echo "Requesting SSH certificate for '${FREEIPA_USERNAME}'..."
  if ! vault write -address="${VAULT_SERVER_ADDRESS}" -ca-cert="${VAULT_CA_CERT_PATH}" \
      -field=signed_key "ssh/sign/${VAULT_SSH_ROLE}" \
      "valid_principals=${FREEIPA_USERNAME}" > "${SSH_CERT_PATH}"; then
    echo "FAILURE: Failed to obtain SSH certificate from Vault." >&2
    return 1
  fi
  echo "SUCCESS: Certificate saved to '${SSH_CERT_PATH}'."
}

# PuppyGirl Vault SSH Aliases
alias cert="get_vault_ssh_cert"
alias pssh="ssh -i ~/.ssh/puppygirl_ssh_key-cert.pub"

### PUPPYGIRL VAULT SSH SETUP END ###
EOF

    print_status "Added get_vault_ssh_cert function and aliases to $config_file"
}

# Main installation function
main() {
    print_status "PuppyGirl Vault SSH Certificate Setup"
    print_status "======================================"
    
    # Install Vault CLI if needed
    install_vault_cli
    
    # Detect shell configuration file
    config_file=$(detect_shell)
    print_status "Detected shell configuration file: $config_file"
    
    # Check if installation already exists
    if ! check_existing_installation "$config_file"; then
        remove_existing_installation "$config_file"
    fi
    
    # Add the function and aliases
    add_to_config "$config_file"
    
    print_status "Installation complete!"
    print_status ""
    print_status "Available commands:"
    print_status "  cert [username]     - Get Vault SSH certificate (defaults to current user)"
    print_status "  pssh <user>@<host>  - SSH using the certificate"
    print_status ""
    print_status "How it works:"
    print_status "NOTE: You must be connected to the PuppyGirl VPN as well as have 2FA configured on your SSO account."
    print_status "If you do not have 2FA configured, please set it up first at https://sso.puppygirl.io"
    print_status "  1. The 'cert' command will generate an SSH certificate using your LDAP"
    print_status "     Usage: cert [username] (if no username is provided, it defaults to the current user)"
    print_status ""
    print_status "  2. The certificate is valid for 24 hours and saved as ~/.ssh/puppygirl_ssh_key-cert.pub"
    print_status "     Use 'cert' to renew the certificate as needed"
    print_status ""
    print_status "  3. Use 'pssh' to SSH with the certificate authentication"
    print_status "    Example: pssh <LDAP>@<hostname/IP>"
    print_status ""
    print_status ""
    print_status "To activate the new commands in your current session:"
    print_status "  source $config_file"
    print_status ""
    print_status "Or simply restart your shell session."
    print_status ""
    print_status "If you want to source automatically, run this script with:"
    print_status "  curl -sSL <github-url> | bash && source $config_file"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
