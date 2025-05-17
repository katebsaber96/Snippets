#!/bin/bash

LOG_PREFIX="[DOCKER_SETUP]"

# Check if a proxy argument is provided
# This proxy is used for the Docker GPG key download and APT
if [ -z "$1" ]; then
  echo "$LOG_PREFIX Usage: $0 <proxy_url>"
  echo "$LOG_PREFIX Example: $0 http://[username]:[password]@[host]:[port]"
  exit 1
fi

# Ensure this proxy is accessible and correctly configured.
check_proxy() {
  local proxy_url="$1"
  local test_url="http://ip-api.com/json" # Using ip-api.com for proxy testing as it is not restricted in Iran
  local timeout_seconds=15 # Increased timeout slightly for API call

  # Check if jq is installed, as it's needed to parse the JSON response
  if ! command -v jq &> /dev/null; then
    echo "$LOG_PREFIX Error: 'jq' is not installed, but it's required for the proxy check."
    echo "$LOG_PREFIX Please install jq to proceed. On Debian/Ubuntu, you can use: sudo apt-get install jq"
    return 1
  fi

  echo "$LOG_PREFIX Testing proxy connectivity by fetching IP info from $test_url via $proxy_url..."
  if curl_response=$(curl -sS -x "$proxy_url" --connect-timeout "$timeout_seconds" "$test_url"); then
    if echo "$curl_response" | jq -e '.status == "success"' > /dev/null 2>&1; then
      echo "$LOG_PREFIX Proxy test successful: Able to fetch data from $test_url via $proxy_url and received success status."
      local country=$(echo "$curl_response" | jq -r '.country')
      if [[ "$country" == "Iran" ]]; then
        echo "$LOG_PREFIX Error: Proxy's IP is located in Iran and can not be used for docker installation."
        echo "$LOG_PREFIX Response from ip-api.com:"
        echo "$LOG_PREFIX $curl_response" # Prefixed the selected line
        return 1
      fi
      return 0
    else
      echo "$LOG_PREFIX Error: Proxy test failed. Received a response from $test_url, but it was not successful."
      echo "$LOG_PREFIX Response from ip-api.com:"
      echo "$LOG_PREFIX $curl_response" # Prefixed
      echo "$LOG_PREFIX Please check your proxy settings and ensure it can correctly access external services."
      return 1
    fi
  else
    local curl_exit_code=$?
    echo "$LOG_PREFIX Error: Proxy test failed. Unable to connect to $test_url via $proxy_url."
    echo "$LOG_PREFIX Curl exit code: $curl_exit_code"
    echo "$LOG_PREFIX Please check your proxy URL, credentials, and network connection."
    return 1
  fi
}

if ! check_proxy "$1"; then
  exit 1
fi

PROXY="$1"
echo "$LOG_PREFIX Using proxy: $PROXY"

# Setup APT proxy
echo "$LOG_PREFIX ###################################"
echo "$LOG_PREFIX Starting APT proxy configuration..."
echo "$LOG_PREFIX ###################################"

PROXY_CONFIG=$(cat <<EOF
Acquire {
  HTTP::proxy "${PROXY}";
  HTTPS::proxy "${PROXY}";
}
EOF
)

APT_PROXY_FILE="/etc/apt/apt.conf.d/proxy.conf"

echo "$LOG_PREFIX Writing the following APT proxy configuration to $APT_PROXY_FILE:"
echo "$LOG_PREFIX $PROXY_CONFIG" # Show what will be written, prefixed
echo "$PROXY_CONFIG" | sudo tee "$APT_PROXY_FILE" > /dev/null

if [ $? -eq 0 ]; then
  echo "$LOG_PREFIX Successfully wrote APT proxy configuration to $APT_PROXY_FILE"
  echo "$LOG_PREFIX Contents of $APT_PROXY_FILE:" # This line is prefixed
  sudo cat "$APT_PROXY_FILE" # The actual cat output is not prefixed
else
  echo "$LOG_PREFIX Error: Failed to write APT proxy configuration to $APT_PROXY_FILE"
  exit 1
fi


echo "$LOG_PREFIX ###################################"
echo "$LOG_PREFIX Starting Docker repository setup..."
echo "$LOG_PREFIX ###################################"


# Removing previous docker installation
echo "$LOG_PREFIX Removing previous docker installation"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done
dpkg -l | grep -i docker | awk '{print $2}' | xargs sudo apt purge -y
if [ $? -eq 0 ]; then
  echo "$LOG_PREFIX Successfully removed previous docker installation."
else
  echo "$LOG_PREFIX Error: Failed to remove previous docker installation."
  # Consider whether to exit here or continue
fi

# Install prerequisit tools for installing docker
sudo apt-get update # This output will be from apt-get itself
sudo apt-get install -y ca-certificates curl jq # Added jq here as well for convenience, and -y


# Add docker repository
sudo install -m 0755 -d /etc/apt/keyrings
echo "$LOG_PREFIX Created /etc/apt/keyrings directory (if it didn't exist)."

echo "$LOG_PREFIX Downloading Docker GPG key using proxy: $PROXY..."
sudo curl -x "$PROXY" -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
if [ $? -ne 0 ]; then
  echo "$LOG_PREFIX Error: Failed to download Docker GPG key. Please check your proxy settings ($PROXY) and network connection."
  exit 1
fi
echo "$LOG_PREFIX Docker GPG key downloaded."

sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "$LOG_PREFIX Set permissions for Docker GPG key."

echo "$LOG_PREFIX Adding Docker repository to APT sources..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
if [ $? -ne 0 ]; then
  echo "$LOG_PREFIX Error: Failed to add Docker repository to sources.list.d."
  exit 1
fi
echo "$LOG_PREFIX Docker repository added successfully."


# Update package list again to include Docker packages from the new repo
sudo apt-get update # This output will be from apt-get itself
echo "$LOG_PREFIX Package list updated after adding Docker repository."


# Install docker
echo "$LOG_PREFIX Installing Docker packages..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if [ $? -eq 0 ]; then
  echo "$LOG_PREFIX Successfully installed docker."
else
  echo "$LOG_PREFIX Error: Failed to install docker."
  exit 1
fi

echo "$LOG_PREFIX Docker repository setup completed."


echo "$LOG_PREFIX ###################################"
echo "$LOG_PREFIX Removing APT Proxy..."
echo "$LOG_PREFIX ###################################"

sudo rm -f "$APT_PROXY_FILE"
if [ $? -eq 0 ]; then
  echo "$LOG_PREFIX Successfully removed $APT_PROXY_FILE"
else
  echo "$LOG_PREFIX Error: Failed to remove $APT_PROXY_FILE"
  exit 1 
fi


echo "$LOG_PREFIX ###################################"
echo "$LOG_PREFIX Docker post installation setup"
echo "$LOG_PREFIX ###################################"

# Define the current username
if [ -n "$SUDO_USER" ]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME="$USER"
fi
echo "$LOG_PREFIX Determined user for docker group: $USER_NAME"

# Add user to docker group
echo "$LOG_PREFIX Adding $USER_NAME to docker group"
sudo usermod -aG docker "$USER_NAME"
if [ $? -eq 0 ]; then
  echo "$LOG_PREFIX User $USER_NAME successfully added to the docker group."
  echo "$LOG_PREFIX NOTE: You may need to log out and log back in for this change to take full effect,"
  echo "$LOG_PREFIX or run 'newgrp docker' in your current terminal session (this starts a new shell)."
else
  echo "$LOG_PREFIX Error: Failed to add user $USER_NAME to the docker group."
  exit 1;
fi

# Configure Arvan Repository
echo "$LOG_PREFIX Configuring Arvan Repository"

ARVAN_CONFIG=$(cat <<EOF
{
  "insecure-registries" : ["https://docker.arvancloud.ir"],
  "registry-mirrors": ["https://docker.arvancloud.ir"]
}
EOF
)

DOCKER_CONFIG_FILE="/etc/docker/daemon.json"

echo "$LOG_PREFIX Writing the Arvan Repository configuration to $DOCKER_CONFIG_FILE:"
echo "$LOG_PREFIX $ARVAN_CONFIG" # Show what will be written, prefixed
echo "$ARVAN_CONFIG" | sudo tee "$DOCKER_CONFIG_FILE" > /dev/null
if [ $? -ne 0 ]; then
    echo "$LOG_PREFIX Error: Failed to write Arvan Repository configuration to $DOCKER_CONFIG_FILE"
    exit 1;
fi


echo "$LOG_PREFIX Logging out of docker.io (this may not produce output if not logged in)"
sudo docker logout

echo "$LOG_PREFIX Restarting Docker service..."
sudo systemctl restart docker
if [ $? -eq 0 ]; then
  echo "$LOG_PREFIX Docker service restarted successfully."
else
  echo "$LOG_PREFIX Error: Failed to restart Docker service."
  exit 1;
fi


echo "$LOG_PREFIX ###################################"
echo "$LOG_PREFIX Script finished successfully."
echo "$LOG_PREFIX ###################################"
