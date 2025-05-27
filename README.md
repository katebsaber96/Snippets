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
  
- Useful commands

  - **Clear Ubuntu terminal history ([original answer](https://askubuntu.com/questions/191999/how-to-clear-bash-history-completely)):** 

    To clear the bash history completely on the server, open terminal and type:

    ```bash
    cat /dev/null > ~/.bash_history
    ```

    One drawback is that history entries reside in memory and are subsequently written to `~/.bash_history` by the OS. To mitigate this, the following command can be used:

    ```bash
    cat /dev/null > ~/.bash_history && history -c && exit
    ```

    

    **Be careful:**

    These commands are **only** tested against **Ubuntu 22.04** and work fine (As of May 27th, 2025). 

    

  - **Extend Ubuntu file system:**

    First run the following command to see the overall view of the file system:

    ```bash
    lsblk
    ```

    This should result in such an output:

    ```bash
    NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
    loop0                       7:0    0 63.9M  1 loop /snap/core20/2318
    loop1                       7:1    0   87M  1 loop /snap/lxd/29351
    loop2                       7:2    0 38.8M  1 loop /snap/snapd/21759
    sda                         8:0    0  200G  0 disk 
    ├─sda1                      8:1    0    1M  0 part 
    ├─sda2                      8:2    0    2G  0 part /boot
    └─sda3                      8:3    0  198G  0 part 
      └─ubuntu--vg-ubuntu--lv 253:0    0   98G  0 lvm  /
    sr0                        11:0    1 1024M  0 rom
    ```

    As obvious in the sample output, we have 198GB of disk available in `sda3` but `ubuntu--vg-ubuntu--lv` is only using 98GB of that. To fix this you can use the following commands:

    ```bash
    lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
    
    resize2fs /dev/ubuntu-vg/ubuntu-lv
    ```

    **Be careful:**

    These commands are **only** tested against **Ubuntu 22.04** and work fine (As of May 27th, 2025). Both of these commands require **sudo access** and **change the file system**. There is potential for data loss while using these commands, so **use with caution** and **backup** your files before running.

