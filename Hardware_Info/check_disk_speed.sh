#!/bin/bash

# Ensure smartctl is installed
if ! command -v smartctl &> /dev/null
then
    echo "smartctl not found, installing smartmontools..."
    apt update && apt install -y smartmontools
fi

echo "Checking SAS/SATA negotiated speed and size for all /dev/sd* disks..."
printf "%-8s %-12s %-20s %-10s\n" "Disk" "Drive Type" "Link Speed" "Size"

# Loop through all sd* devices
for disk in /dev/sd[a-z]
do
    # Skip if not a block device
    [ -b "$disk" ] || continue

    drive_type="Unknown"
    link_speed="Unknown"

    # Get disk size in human-readable format
    size=$(lsblk -b -dn -o SIZE "$disk")
    # Convert bytes to TB/GiB for readability
    if [ "$size" -ge 1099511627776 ]; then
        size=$(echo "scale=2; $size/1099511627776" | bc)TB
    elif [ "$size" -ge 1073741824 ]; then
        size=$(echo "scale=2; $size/1073741824" | bc)GB
    else
        size=$(echo "scale=2; $size/1048576" | bc)MB
    fi

    # Run smartctl to get SAS Version / Negotiated link rate
    smartctl_output=$(smartctl -a "$disk" 2>/dev/null)

    sas_version=$(echo "$smartctl_output" | grep -i 'SAS Version')
    sas_link=$(echo "$smartctl_output" | grep -i 'Negotiated link rate')

    # Check for SATA info if SAS info missing
    if [ -z "$sas_version" ]; then
        # Look for SATA speed in smartctl info
        sata_speed=$(echo "$smartctl_output" | grep -i 'SATA Version is' | awk -F: '{print $2}' | xargs)
        if [ -n "$sata_speed" ]; then
            drive_type="SATA"
            link_speed="$sata_speed"
        fi
    else
        drive_type="SAS"
        link_speed=$(echo "$sas_link" | awk -F: '{print $2}' | xargs)
    fi

    printf "%-8s %-12s %-20s %-10s\n" "$disk" "$drive_type" "$link_speed" "$size"

done

echo "--------------------------------------------------"
echo "Done."
