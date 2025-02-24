#!/bin/bash

clear

#-e make sure the script quits if there's any exit code other than 0.
set -e

#-e enable interpretation of backslash escapes
echo -e "\nHello $USER.\n"

# Make sure the user is running the script as root.
if [[ $EUID -ne 0 ]]; then
    echo "You need to run this script with root privileges!"
    sleep 0.5
    echo -e "Quitting...\n"
    sleep 0.5
    exit 1
fi

## USER CONFIGURATION ##
# Create users from users-array and assign each to user-variable
users=("Muhammad" "David" "DanielPM" "Patrick" "DanielH")
for user in "${users[@]}"; do
    useradd -m "$user"
done
echo -e "\n> Users has been created.\n"
sleep 0.5

# Prompt to set default-password for all users
echo "Enter a default password for all the newly created users."
echo "(This password will have to be changed on the first login.)"
echo "Set default password: "
read -rp "Set default password: " default_password

# Changes default password to entered password by user
for user in "${users[@]}"; do
    echo "$user":"$default_password" | chpasswd
done


## System Update and Upgrade
echo "Updating system packages."
echo "This will take a while.."
sleep 2
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get -y upgrade && apt-get -y autoremove && apt-get -y autoclean

## GROUP CONFIGURATION ##
# Create new group g2members, /opt/g2members-dir and assign permissions
echo "Creating a new group for all of the newly created users."
sleep 3
group_name="g2members"
groupadd $group_name
mkdir -p /opt/"$group_name"
chown -R :g2members /opt/g2members
chmod g+rwx /opt/"$group_name"
chmod u+rwx /opt/"$group_name"
chmod o-rwx /opt/"$group_name"
chmod g+s /opt/"$group_name"
sleep 0.5
echo -e "> Group folder /opt/g2members has been created with group ownership.\n"

# Append users to g2members-group
for user in "${users[@]}"; do
    usermod -aG $group_name "$user"
done
echo -e "\n> Group 'g2members' has been created and assigned to the new users.\n"

# Force new password upon first login
for user in "${users[@]}"; do
    passwd -e "$user"
done

# Remove need to type password with sudo-commands
for user in "${users[@]}"; do
    echo "$user ALL=(ALL:ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/"$user"
done

## SSH-CONFIGURATION ##
# Install SSH-Server
# Function to grep "openssh-server"
is_pkg() {
    dpkg -l | grep -qw "$1"
}
if is_pkg "openssh-server"; then
    echo "OpenSSH Server is already installed."
else
    echo "OpenSSH Server is not installed. Installing it now..."
    apt install -y openssh-server
fi

# Check if the SSH service is running
# is-active return active or inactive and --quiet return only status code
if systemctl is-active --quiet ssh; then
    echo "SSH service is running."
else
    echo "SSH service is not running. Starting it now..."
    systemctl start ssh
    systemctl enable ssh
    echo "SSH service has been started and enabled."
fi

# Change Default port from 22 to 9999
if ! sed -i 's/^#Port .*/Port 9999/' /etc/ssh/sshd_config
then
    echo "port config failed!"
fi

# Change login-options via ssh to only allow login-in via Pubkey
if ! sed -i \
    -e 's/^#PasswordAuthentication yes/PasswordAuthentication no/' \
    -e 's/^PasswordAuthentication .*/PasswordAuthentication no/' \
    -e 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' \
    -e 's/^PubkeyAuthentication .*/PubkeyAuthentication yes/' \
    -e 's/^#KbdInteractiveAuthentication yes/KbdInteractiveAuthentication no/' \
    -e 's/^KbdInteractiveAuthentication .*/KbdInteractiveAuthentication no/' \
    -e 's/^#GSSAPIAuthentication yes/GSSAPIAuthentication no/' \
    -e 's/^GSSAPIAuthentication .*/GSSAPIAuthentication no/' \
    /etc/ssh/sshd_config
then
    echo "failed to change sshconfig pubkey only"
fi

sed -i '/^Include/s/^/#/' /etc/ssh/sshd_config

# Only allow members of the group to login via ssh
if ! sed -i '$ a AllowUsers Muhammad David DanielPM Patrick DanielH' /etc/ssh/sshd_config
then
    echo "failed to add allowed users to /etc/ssh/sshd_config"
fi

# Restart ssh-service
if ! systemctl restart ssh.service
then
    echo "Failed to restart ssh.service"
fi

## Firewall configuration ##
# Disable ufw
ufw disable
systemctl disable ufw
systemctl stop ufw

# Install firewalld
apt install -y firewalld
systemctl start firewalld
systemctl enable firewalld

# Check if firewalld is active
if ! systemctl is-active --quiet firewalld; then
    echo "Failed to start firewalld"
    exit 1
fi

# Firewalld configuration
# Blocking all incoming connections except SSH-port 9999.
# Allowing all outgoing connections
firewall-cmd --complete-reload
firewall-cmd --set-default-zone=drop
firewall-cmd --permanent --zone=drop --add-port=9999/tcp
firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -j ACCEPT
firewall-cmd --reload
echo "Firewall configured successfully"

## DOCKER CONFIGURATION ##
# Add Docker with docker oficial ubuntu online snippet
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do  apt-get remove -y $pkg; done
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc


# Add the repository to Apt sources
# Only jammy-version for Ubuntu 22.04.5
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  jammy stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Test docker with hello-world container
docker run hello-world


# Check if group 'docker' has been created
if getent group docker > /dev/null 2>&1; then
    echo "The 'docker' group exists."
else
    echo "The 'docker' group does not exist. check installation!"
    exit 1
fi

# Append each user to 'docker' group
# Ensures each user can run docker-commands without sudo
for user in "${users[@]}"; do
    usermod -aG docker "$user"
    echo "Added $user to the docker group."
done
echo "${users[*]} can now run Docker commands without using sudo."
