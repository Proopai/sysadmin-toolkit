#!/bin/bash

MAP_FILE="/etc/disk_array_map.conf"
COLUMN_PATTERN="%-11s %-17s %-20s %-12s %-24s %-24s %-18s %-10s %-7s %-12s\n"

# Ensure smartctl exists
if ! command -v smartctl &> /dev/null; then
    echo "Installing smartmontools..."
    apt update && apt install -y smartmontools
fi

# Load existing controller map
declare -A PCI_MAP
if [ -f "$MAP_FILE" ]; then
    while IFS="=" read -r pci name; do
        PCI_MAP["$pci"]="$name"
    done < "$MAP_FILE"
fi

save_map() {
    : > "$MAP_FILE"
    for key in "${!PCI_MAP[@]}"; do
        echo "$key=${PCI_MAP[$key]}" >> "$MAP_FILE"
    done
}

echo
echo "Checking SAS/SATA/USB version and negotiated speed for all /dev/sd* disks..."
echo

printf "$COLUMN_PATTERN" \
"Disk" "Drive Type" "Link Info" "Size" "Manufacturer" "Model" "Serial" "Array" "Slot" "PowerOnHours"

# Build sdX -> persistent ID map
declare -A ID_MAP
for idpath in /dev/disk/by-id/*; do
    [ -e "$idpath" ] || continue
    realdev=$(readlink -f "$idpath")
    base=$(basename "$realdev")
    if [[ "$idpath" == *usb* ]]; then
        ID_MAP["$base"]="usb"
    elif [ -z "${ID_MAP[$base]}" ]; then
        ID_MAP["$base"]="ata"
    fi
done

for disk in /dev/sd[a-z]; do
    [ -b "$disk" ] || continue
    base=$(basename "$disk")
    disk_id="${ID_MAP[$base]}"

    # --- Size ---
    size_bytes=$(lsblk -b -dn -o SIZE "$disk")
    if [ "$size_bytes" -ge 1099511627776 ]; then
        size=$(echo "scale=2; $size_bytes/1099511627776" | bc)TB
    elif [ "$size_bytes" -ge 1073741824 ]; then
        size=$(echo "scale=2; $size_bytes/1073741824" | bc)GB
    else
        size=$(echo "scale=2; $size_bytes/1048576" | bc)MB
    fi

    drive_type="Unknown - Bad?"
    link_info="Unknown - Bad?"
    manufacturer=""
    model="Unknown"
    serial="Unknown"
    array="Unknown"
    slot="N/A"
    power_on_hours="N/A"

    smartctl_output=$(smartctl -i "$disk" 2>/dev/null)
    smartctl_attrs=$(smartctl -A "$disk" 2>/dev/null)

    # --- Model & Serial ---
    model=$(echo "$smartctl_output" | awk -F: '/Device Model|Product:/ {print $2}' | xargs | head -n1)
    serial=$(echo "$smartctl_output" | awk -F: '/Serial Number/ {print $2}' | xargs)

    # --- Manufacturer Detection ---
    manufacturer=$(echo "$smartctl_output" | awk -F: '/Vendor:/ {print $2}' | xargs)
    if [ -z "$manufacturer" ] || [ "$manufacturer" = "ATA" ]; then
        manufacturer=$(echo "$smartctl_output" | awk -F: '/Model Family:/ {print $2}' | xargs)
    fi

    sys_vendor_file="/sys/block/$base/device/vendor"
    if [ -r "$sys_vendor_file" ] && [ "$manufacturer" != "ATA" ] && [ -z "$manufacturer" ]; then
        manufacturer=$(cat "$sys_vendor_file" | xargs)
    fi

    if [ -z "$manufacturer" ] || [ "$manufacturer" = "ATA" ]; then
        case "$model" in
            ST* ) manufacturer="Seagate" ;;
            WDC*|WD* ) manufacturer="Western Digital" ;;
            HGST*|HUH* ) manufacturer="Hitachi" ;;
            SAMSUNG*|MZ* ) manufacturer="Samsung" ;;
            INTEL* ) manufacturer="Intel" ;;
            KINGSTON* ) manufacturer="Kingston" ;;
            CRUCIAL* ) manufacturer="Crucial" ;;
            * ) manufacturer="Unreadable" ;;
        esac
    fi

    [ -n "$manufacturer" ] && manufacturer=$(echo "$manufacturer" | awk '{print $1" "$2}' | xargs)

    # --- Slot & PCI ---
    sys_path=$(readlink -f /sys/block/$base/device)
    slot=$(echo "$sys_path" | grep -oE 'target[0-9]+:[0-9]+:[0-9]+' | awk -F: '{print $3}')
    [ -z "$slot" ] && slot="N/A"

    pci_addr=$(echo "$sys_path" | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | head -n1)

    # --- Array Detection ---
    if [[ "$disk_id" == "usb" ]]; then
        array="USB"
    else
        if [ -n "${PCI_MAP[$pci_addr]}" ]; then
            array="${PCI_MAP[$pci_addr]}"
        else
            echo
            echo "New Controller Detected: PCI $pci_addr"
            read -p "Enter Array Name (Example: Slammer / Server / Backup): " newname
            PCI_MAP["$pci_addr"]="$newname"
            save_map
            array="$newname"
        fi
    fi

    # --- Drive Type & Link Info ---
    if [ "$array" = "USB" ]; then
        drive_type="USB"
        link_info="USB"
    else
        sas_ver=$(echo "$smartctl_output" | grep -i "SAS Version" | awk -F: '{print $2}' | xargs)
        sas_rate=$(echo "$smartctl_output" | grep -i "Negotiated Link Rate" | awk -F: '{print $2}' | xargs)
        sata_ver=$(echo "$smartctl_output" | grep -i "SATA Version is" | awk -F: '{print $2}' | xargs | sed 's/,//')
        sata_curr=$(echo "$smartctl_output" | grep -i "SATA Version is" | grep -o "current [0-9.]*" | awk '{print $2 " Gb/s"}')

        if [ -n "$sas_ver" ]; then
            drive_type="SAS"
            link_info="$sas_ver $sas_rate"
        elif [ -n "$sata_ver" ]; then
            drive_type="SATA"
            link_info="$sata_ver $sata_curr"
            link_info=$(echo "$link_info" | sed 's/(current.*//')
        else
            drive_type="Unknown - Bad?"
            link_info="Unknown - Bad?"
        fi
    fi

    # --- Power-On Hours ---
    # Try attribute 9 first; fallback to raw string if numeric not found
    power_on_hours=$(echo "$smartctl_attrs" | awk '$1==9 {print $10}')
    [ -z "$power_on_hours" ] && power_on_hours="N/A"

    printf "$COLUMN_PATTERN" \
    "$disk" "$drive_type" "$link_info" "$size" "$manufacturer" "$model" "$serial" "$array" "$slot" "$power_on_hours"

done

echo "--------------------------------------------------"
echo "Done."
