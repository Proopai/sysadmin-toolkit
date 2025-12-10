#!/bin/bash
# Update Base Apt Packages
apt update
apt upgrade
# Steamcmd Pre-Reqs
apt install software-properties-common
apt-add-repository non-free
dpkg --add-architecture i386
apt update
# Install Steamcmd
apt install steamcmd

# Make steamcmd executable from anywhere
ln -s /usr/games/steamcmd /usr/bin

# Reconfigure Locals to include en_US.UTF8 UTF8 for proper operation of steamcmd
echo "locales locales/default_environment_locale select en_US.UTF-8 UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales

# Execute SteamCMD to update it to the latest version
steamcmd
