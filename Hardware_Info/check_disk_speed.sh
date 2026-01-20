#!/bin/bash

# Ensure smartctl is installed
if ! command -v smartctl &> /dev/null
then
    echo "smartctl not found, installing smartmontools..."
    apt update && apt install -y smartmontools
fi

echo "Checking SAS/SATA version and negotiated speed for all /dev/sd* disks..."
printf "%-8s %-12s %-25s %-10s\n" "Disk" "Drive Type" "Link Info" "Size"

for disk in /dev/sd[a-z]
do
    [ -b "$disk" ] || continue

    # Get disk size from lsblk
    size_bytes=$(lsblk -b -dn -o SIZE "$disk")
    if [ "$size_bytes" -ge 1099511627776 ]; then
        size=$(echo "scale=2; $size_bytes/1099511627776" | bc)TB
    elif [ "$size_bytes" -ge 1073741824 ]; then
        size=$(echo "scale=2; $size_bytes/1073741824" | bc)GB
    else
        size=$(echo "scale=2; $size_bytes/1048576" | bc)MB
    fi

    # Default values
    drive_type="Unknown"
    link_info="Unknown"

    # smartctl interface info
    smartctl_output=$(smartctl -i "$disk" 2>/dev/null)

    # Check for SAS
    sas_ver=$(echo "$smartctl_output" | grep -i "SAS Version" | awk -F: '{print $2}' | xargs)
    sas_rate=$(echo "$smartctl_output" | grep -i "Negotiated Link Rate" | awk -F: '{print $2}' | xargs)

    if [ -n "$sas_ver" ]; then
        drive_type="SAS"
        link_info="$sas_ver $sas_rate"
    else
        # Check for SATA
        sata_ver=$(echo "$smartctl_output" | grep -i "SATA Version is" | awk -F: '{print $2}' | xargs | sed 's/,//')
        sata_curr=$(echo "$smartctl_output" | grep -i "SATA Version is" | grep -o "current [0-9.]*" | awk '{print $2 " Gb/s"}')
        if [ -n "$sata_ver" ]; then
            drive_type="SATA"
            link_info="$sata_ver $sata_curr"
            # Strip "(current ...)" if smartctl prints it
            link_info=$(echo "$link_info" | sed 's/(current.*//')
        fi
    fi

    printf "%-8s %-12s %-25s %-10s\n" "$disk" "$drive_type" "$link_info" "$size"

done

echo "--------------------------------------------------"
echo "Done."
