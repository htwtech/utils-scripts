#!/bin/bash
#set -x # uncomment to enable debug

declare -A REQUIRED_CMDS_PACKAGES=(
    [nvme]="nvme-cli"
    [lspci]="pciutils"
    [grep]="grep"
    [awk]="gawk"
    [sed]="sed"
)

for cmd in "${!REQUIRED_CMDS_PACKAGES[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        PACKAGE=${REQUIRED_CMDS_PACKAGES[$cmd]}
        echo "❗ Error: Required command '$cmd' is not installed."
        echo "👉 You can install it using:"
        echo "    sudo apt install $PACKAGE"
        exit 1
    fi
done


echo "🔎 Searching for NVMe devices..."
mapfile -t NVME_DEVICES < <(sudo nvme list | grep '^/dev/nvme' | awk '{print $1}')

if [ ${#NVME_DEVICES[@]} -eq 0 ]; then
    echo "❗ No NVMe devices found."
    exit 1
fi

echo "✅ Found ${#NVME_DEVICES[@]} NVMe devices."

declare -a SUMMARY=()

for DEV in "${NVME_DEVICES[@]}"; do
    echo "-------------------------------"
    echo "📦 Checking device: $DEV"

    DEVICE_NAME=$(basename "$DEV")


    sudo nvme id-ctrl "$DEV" | grep -E 'mn|sn|fr|subnqn'
    echo ""


    echo "📊 SMART health data:"
    SMART_OUTPUT=$(sudo nvme smart-log "$DEV")
    echo "$SMART_OUTPUT" | grep -E 'temperature|available_spare|percentage_used|Data Units Written|Data Units Read'


    WEAR=$(echo "$SMART_OUTPUT" | grep 'percentage_used' | awk '{print $3}' | tr -d '%')
    if [ -z "$WEAR" ]; then
        WEAR="?"
    fi

    echo ""


    echo "🖧 Checking PCIe connection:"
    NVME_DISK=$(basename "$DEV" | sed 's/n[0-9]*$//')
    PCI_PATH=$(readlink -f /sys/class/nvme/$NVME_DISK/device)
    PCI_BDF=$(basename "$PCI_PATH")


    if [[ "$PCI_BDF" != 0000:* ]]; then
        PCI_BDF="0000:$PCI_BDF"
    fi

    if [ -n "$PCI_BDF" ]; then
        echo "    🔎 Found PCIe device: $PCI_BDF"
        PCI_INFO=$(sudo lspci -s "$PCI_BDF" -vv)
        # Display PCIe header (controller model info)
        PCI_HEADER=$(echo "$PCI_INFO" | head -n 1)
        echo "🧩 $PCI_HEADER"

   
        SUBSYSTEM_STR=$(echo "$PCI_INFO" | grep -m1 "Subsystem:" | sed 's/^[ \t]*//')
        if [ -n "$SUBSYSTEM_STR" ]; then
        echo "🛡️ $SUBSYSTEM_STR"
        fi

        SUPPORTED_LINE=$(echo "$PCI_INFO" | grep "LnkCap:")
        CURRENT_LINE=$(echo "$PCI_INFO" | grep "LnkSta:")

        SUPPORTED_SPEED=$(echo "$SUPPORTED_LINE" | grep -o 'Speed [^,]*' | awk '{print $2}')
        SUPPORTED_WIDTH=$(echo "$SUPPORTED_LINE" | grep -o 'Width x[0-9]*' | awk '{print $2}')
        CURRENT_SPEED=$(echo "$CURRENT_LINE" | grep -o 'Speed [^,]*' | awk '{print $2}')
        CURRENT_WIDTH=$(echo "$CURRENT_LINE" | grep -o 'Width x[0-9]*' | awk '{print $2}')

        echo "        $SUPPORTED_LINE"
        echo "        $CURRENT_LINE"

     
        MAX_LINK_SPEED=$(cat /sys/bus/pci/devices/$PCI_BDF/max_link_speed 2>/dev/null || echo "?")
        CURRENT_LINK_SPEED=$(cat /sys/bus/pci/devices/$PCI_BDF/current_link_speed 2>/dev/null || echo "?")

        if [[ "$CURRENT_SPEED" != "$SUPPORTED_SPEED" ]]; then
            echo "⚠️  Warning! PCIe link speed is downgraded: running at $CURRENT_SPEED instead of $SUPPORTED_SPEED."
        fi


        echo ""
        echo "🛠️ Checking PCIe errors:"
        AER_BLOCK=$(echo "$PCI_INFO" | grep -A 10 "Advanced Error Reporting")
        ERRORS="No"

        if [ -n "$AER_BLOCK" ]; then
            echo "$AER_BLOCK" | sed 's/^/    /'

            if echo "$AER_BLOCK" | grep -q '+'; then
                echo "⚠️  Warning! Detected PCIe transmission errors!"
                ERRORS="Yes"
            fi
        else
            echo "    ❗ Advanced Error Reporting not supported for this device."
        fi


        SUMMARY+=("$DEVICE_NAME" "$WEAR%" "$CURRENT_SPEED" "$CURRENT_WIDTH" "$SUPPORTED_SPEED" "$SUPPORTED_WIDTH" "$CURRENT_LINK_SPEED" "$MAX_LINK_SPEED" "$ERRORS")

    else
        echo "    ⚠️  Could not find PCIe address for $DEV"
        SUMMARY+=("$DEVICE_NAME" "?" "?" "?" "?" "?" "?" "?" "No")
    fi

    echo ""
done


echo "==============================="
printf "%-12s %-8s %-14s %-14s %-16s %-16s %-20s %-20s %-10s\n" "Device" "Wear" "Current_Speed" "Current_Width" "Supported_Speed" "Supported_Width" "Current_PCIe" "Max_PCIe" "Errors"
echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------"
for ((i=0; i<${#SUMMARY[@]}; i+=9)); do
    printf "%-12s %-8s %-14s %-14s %-16s %-16s %-20s %-20s %-10s\n" \
    "${SUMMARY[i]}" "${SUMMARY[i+1]}" "${SUMMARY[i+2]}" "${SUMMARY[i+3]}" "${SUMMARY[i+4]}" "${SUMMARY[i+5]}" "${SUMMARY[i+6]}" "${SUMMARY[i+7]}" "${SUMMARY[i+8]}"
done

echo ""
echo "🎯 NVMe health check completed."
