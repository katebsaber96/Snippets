#!/bin/bash

# Script to install Docker in Iran using a proxy to bypass restrictions
# Improved with better error handling, cleanup, input validation, and modularity

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

LOG_PREFIX="[DOCKER_SETUP]"
readonly LOG_PREFIX
VERSION="1.0.0"

# Default timeout for network operations (seconds)
readonly TIMEOUT_SECONDS=15

# Function to log messages with prefix
log() {
    echo "${LOG_PREFIX} $*" >&2
}

# Function to log errors and exit
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Function to validate proxy URL format
validate_proxy_url() {
    local proxy_url="$1"
    # Basic regex to match http(s)://[username:password@]host:port
    if [[ ! "$proxy_url" =~ ^https?://([a-zA-Z0-9_-]+:[^@]+@)?[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        error_exit "Invalid proxy URL format. Expected: http(s)://[username:password@]host:port"
    fi
}

# Function to check proxy connectivity
check_proxy() {
    local proxy_url="$1"
    local test_url="http://ip-api.com/json"

    # Check if jq is installed
    if ! command -v jq >/dev/null 2>&1; then
        error_exit "'jq' is required for proxy validation. Install with: sudo apt-get install jq"
    fi

    log "Testing proxy connectivity via $test_url..."
    local curl_response
    if ! curl_response=$(curl -sS -x "$proxy_url" --connect-timeout "$TIMEOUT_SECONDS" "$test_url" 2>/dev/null); then
        error_exit "Failed to connect to $test_url via $proxy_url. Curl exit code: $?. Check proxy URL and network."
    fi

    if echo "$curl_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        local country
        country=$(echo "$curl_response" | jq -r '.country')
        if [[ "$country" == "Iran" ]]; then
            error_exit "Proxy IP is located in Iran and cannot be used. Response: $curl_response"
        fi
        log "Proxy test successful. Country: $country"
    else
        error_exit "Proxy test failed. Response: $curl_response"
    fi
}

# Function to configure APT proxy
configure_apt_proxy() {
    local proxy_url="$1"
    local apt_proxy_file="/etc/apt/apt.conf.d/proxy.conf"

    local proxy_config
    proxy_config=$(cat <<EOF
Acquire {
  HTTP::proxy "${proxy_url}";
  HTTPS::proxy "${proxy_url}";
}
EOF
)

    log "Configuring APT proxy in $apt_proxy_file..."
    echo "$proxy_config" | sudo tee "$apt_proxy_file" >/dev/null || error_exit "Failed to write APT proxy config to $apt_proxy_file"
    log "APT proxy configured successfully."
}

# Function to remove APT proxy
remove_apt_proxy() {
    local apt_proxy_file="/etc/apt/apt.conf.d/proxy.conf"
    if [[ -f "$apt_proxy_file" ]]; then
        log "Removing APT proxy configuration..."
        sudo rm -f "$apt_proxy_file" || error_exit "Failed to remove $apt_proxy_file"
        log "APT proxy configuration removed."
    fi
}

# Function to clean up previous Docker installations
remove_previous_docker() {
    log "Removing previous Docker installations..."
    local packages=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
    sudo apt-get remove -y "${packages[@]}" >/dev/null 2>&1 || true
    dpkg -l | grep -i docker | awk '{print $2}' | xargs -r sudo apt-get purge -y >/dev/null 2>&1 || true
    log "Previous Docker installations removed."
}

# Function to add Docker repository
add_docker_repository() {
    local proxy_url="$1"

    log "Setting up Docker repository..."
    sudo install -m 0755 -d /etc/apt/keyrings || error_exit "Failed to create /etc/apt/keyrings"

    log "Downloading Docker GPG key..."
    sudo curl -x "$proxy_url" -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || \
        error_exit "Failed to download Docker GPG key. Check proxy ($proxy_url) and network."
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    log "Adding Docker repository to APT sources..."
    local repo_entry
    repo_entry="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu "
    repo_entry+="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable"
    echo "$repo_entry" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null || \
        error_exit "Failed to add Docker repository"

    log "Docker repository added successfully."
}

# Function to install Docker
install_docker() {
    log "Installing Docker packages..."
    sudo apt-get update >/dev/null || error_exit "Failed to update package list"
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null || \
        error_exit "Failed to install Docker packages"
    log "Docker installed successfully."
}

# Function to configure Docker post-installation
configure_docker() {
    local user_name="$1"

    log "Adding $user_name to docker group..."
    sudo usermod -aG docker "$user_name" || error_exit "Failed to add $user_name to docker group"
    log "User $user_name added to docker group. Log out and back in or run 'newgrp docker' to apply."

    log "Configuring ArvanCloud registry..."
    local docker_config
    docker_config=$(cat <<EOF
{
  "insecure-registries": ["docker.arvancloud.ir"],
  "registry-mirrors": ["https://docker.arvancloud.ir"]
}
EOF
)

    local docker_config_file="/etc/docker/daemon.json"
    echo "$docker_config" | sudo tee "$docker_config_file" >/dev/null || \
        error_exit "Failed to write ArvanCloud config to $docker_config_file"
    log "ArvanCloud registry configured."

    log "Logging out of docker.io..."
    sudo docker logout >/dev/null 2>&1 || true

    log "Restarting Docker service..."
    sudo systemctl restart docker || error_exit "Failed to restart Docker service"
    log "Docker service restarted."
}

# Function to install prerequisite tools
install_prerequisites() {
    log "Installing prerequisite tools..."
    sudo apt-get update >/dev/null || error_exit "Failed to update package list"
    sudo apt-get install -y ca-certificates curl jq >/dev/null || error_exit "Failed to install prerequisites"
    log "Prerequisite tools installed."
}

# Trap to ensure APT proxy is removed on exit (success or failure)
cleanup() {
    remove_apt_proxy
}
trap cleanup EXIT

# Main execution
main() {
    if [[ $# -ne 1 ]]; then
        log "Usage: $0 <proxy_url>"
        log "Example: $0 http://username:password@host:port"
        exit 1
    fi

    local proxy_url="$1"
    validate_proxy_url "$proxy_url"
    check_proxy "$proxy_url"

    # Determine user for Docker group
    local user_name
    user_name="${SUDO_USER:-$USER}"
    [[ -z "$user_name" ]] && error_exit "Could not determine current user"

    configure_apt_proxy "$proxy_url"
    install_prerequisites
    remove_previous_docker
    add_docker_repository "$proxy_url"
    install_docker
    configure_docker "$user_name"

    log "Docker installation completed successfully."
    log "Version: $VERSION"
}

main "$@"