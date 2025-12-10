#!/bin/bash
# This script can be run in both an LXC Container and on the Proxmox Host
# if run on proxmox host, it will add driver to DKMS so that driver is added to new kernels
# Current version of script is only designed for Proxmox Environments or LXC Containers

driver_base_url="https://download.nvidia.com/XFree86/Linux-x86_64"
if grep -qa container=lxc /proc/1/environ; then
    echo "Running inside an LXC container."
    is_lxc="y"
elif [[ -f /etc/pve/.version ]]; then
    echo "Running on a Proxmox host."
    is_lxc="n"
else
    echo "Running on a non-Proxmox, non-LXC system."
    exit
fi

latest_driver_info="$(curl -s "${driver_base_url}/latest.txt")"
latest_driver_version="$(echo $latest_driver_info | cut -d' ' -f1)"
latest_driver_path="$(echo $latest_driver_info | cut -d' ' -f2)"
latest_driver_url="$(echo $driver_base_url/$latest_driver_path)"
current_driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"

if dpkg --compare-versions "$latest_driver_version" gt "$current_driver_version"; then
    echo "New Driver Available"  # latest version is newer
    curl -s -o /tmp/nvidia_driver_$latest_driver_version.run $latest_driver_url
    chmod +x /tmp/nvidia_driver_$latest_driver_version.run
    if [[ "$is_lxc" == "y" ]]; then
        # Running inside an LXC Container
        echo "Running inside an LXC Container"
        /tmp/nvidia_driver_$latest_driver_version.run --no-kernel-module --silent --allow-installation-with-running-driver --no-x-check
    else
        # Running on Proxmox Host
        echo "Running on Proxmox Host"
        kernel_version=$(uname -r)
        headers="proxmox-headers-$kernel_version"
        apt install $headers -y
	if dpkg -s dkms 2>/dev/null | grep -q "Status: install ok installed"; then
    	    echo "DKMS is installed, Installing Driver"
        else
            echo "DKMS is NOT installed, Installing DKMS and Driver"
            apt install dkms
        fi
        /tmp/nvidia_driver_$latest_driver_version.run --dkms --silent --allow-installation-with-running-driver --no-x-check
    fi
else
    echo "No Driver Update Available"  # current version is the same or newer
    echo "Currently Installed Driver Version: $current_driver_version"
fi
