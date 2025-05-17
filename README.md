# Snippets

This repository contains useful snippets (e.g. for faster installation of tools or commands to remember)

## List of scripts

- Installation

  - **install_docker_iran.sh**

    This scripts assumes a fresh Ubuntu 22.04 installation and does the following:

    - Removes previous docker installations (**Be Careful**).
    - Installs docker engine and docker compose based on the [official documentation](https://docs.docker.com/engine/install/ubuntu/) (As of May 17th, 2025).
    - Configures [Arvancloud Docker Registry](https://www.arvancloud.ir/fa/dev/docker).
    - Adds the running user to docker group.

    **Prerequisites:**

    - HTTP Proxy: this proxy can be locally installed on the server or could be set up on another accessible server.

    - jq package: This package is used for parsing json responses and could be installed by 

      `apt-get install jq`

    **Setup and Run**

    First download the script using:

    ```bash
    wget https://raw.githubusercontent.com/katebsaber96/Snippets/refs/heads/main/installation/install_docker_in_iran.sh
    ```

    Then run script by running the following command (Please change proxy details accordingly):

    ```bash
    bash install_docker_in_iran.sh http://username:password@host:port
    ```

    **Be careful:**

    This script is **only** tested against **Ubuntu 22.04** and works fine (As of May 17th, 2025). Please read the script before running on other distributions of Linux or other versions of Ubuntu; it might need modifications.

    This script removes all previous installations of docker. This might lead to removal of current images, volumes, networks, and etc.