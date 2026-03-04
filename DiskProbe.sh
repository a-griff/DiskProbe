#!/usr/bin/env bash

###############################################################################
# DiskProbe.sh
#
# Description
# -----------
# DiskProbe is a lightweight Linux disk diagnostic and inspection utility.
# It provides a menu-driven interface to inspect disks, partitions, SMART
# health data, RAID arrays, LVM volumes, filesystem usage, and full storage
# topology.
#
# Requirements
# ------------
# Required utilities typically available on most Linux systems:
#
#   lsblk
#   df
#   blkid
#   awk
#
# Optional utilities (recommended):
#
#   smartctl   (SMART diagnostics)
#   mdadm      (RAID inspection)
#   pvs/vgs/lvs (LVM inspection)
#
# Permissions
# -----------
# Script may run as USER or ROOT.
# ROOT allows SMART diagnostics and surface scans.
#
###############################################################################

set -u
trap "stty sane; echo; echo 'Exiting DiskProbe.'; exit" INT

SMART_AVAILABLE=0
DISKS=()

##############################################
# SMART detection
##############################################

check_smart() {

if command -v smartctl >/dev/null 2>&1; then
SMART_AVAILABLE=1
else
SMART_AVAILABLE=0
echo
echo "WARNING: smartctl not installed — SMART features disabled."
echo
sleep 2
fi

}

##############################################
# Discover disks (FIXED)
##############################################

discover_disks() {

DISKS=()

while read -r line; do

eval "$line"

[[ "$TYPE" != "disk" ]] && continue
[[ "$NAME" == loop* ]] && continue
[[ "$NAME" == ram* ]] && continue

model="$MODEL"
[[ -z "$model" ]] && model="Unknown"

DISKS+=("/dev/$NAME|$model ($SIZE)")

done < <(lsblk -dn -P -o NAME,MODEL,SIZE,TYPE)

}

##############################################
# Disk Health Dashboard
##############################################

disk_health_dashboard() {

clear
echo "DiskProbe - Disk Health Summary"
echo "--------------------------------"
echo

for entry in "${DISKS[@]}"; do

disk=${entry%%|*}
label=${entry#*|}

printf "%-12s %-30s" "$disk" "$label"

if [[ "$SMART_AVAILABLE" -eq 1 && $EUID -eq 0 ]]; then

health=$(smartctl -H "$disk" 2>/dev/null | awk -F: '/SMART overall-health/{print $2}')

temp=$(smartctl -A "$disk" 2>/dev/null | awk '/Temperature_Celsius|Temperature:/ {print $10; exit}')

[[ -z "$temp" ]] && temp="?"

printf " SMART:%s TEMP:%s°C" "$health" "$temp"

else

printf " SMART: unavailable"

fi

echo

done

echo
read -p "Press ENTER to continue..."

}

##############################################
# Storage Topology
##############################################

topology_view() {

while true; do

clear
echo "Storage Topology"
echo "----------------"
echo

lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL

echo
echo "b) Back   h) Home   q) Quit"
echo

read -rp "Selection: " opt

case "$opt" in
b) return ;;
h) stage1_menu ;;
q) exit ;;
*) continue ;;
esac

done
}

##############################################
# LVM inspector
##############################################

lvm_menu() {

while true; do

clear
echo "LVM Information"
echo "---------------"
echo

pvs 2>/dev/null
echo
vgs 2>/dev/null
echo
lvs 2>/dev/null

echo
echo "b) Back   h) Home   q) Quit"
echo

read -rp "Selection: " opt

case "$opt" in
b) return ;;
h) stage1_menu ;;
q) exit ;;
*) continue ;;
esac

done
}

##############################################
# RAID inspector
##############################################

raid_menu() {

while true; do

clear
echo "RAID Information"
echo "----------------"
echo

cat /proc/mdstat
echo

for md in /dev/md*; do

[[ ! -e "$md" ]] && continue

echo
mdadm --detail "$md" 2>/dev/null

done

echo
echo "b) Back   h) Home   q) Quit"
echo

read -rp "Selection: " opt

case "$opt" in
b) return ;;
h) stage1_menu ;;
q) exit ;;
*) continue ;;
esac

done
}

##############################################
# Partition inspection
##############################################

stage3_partition() {

part="$1"

while true; do

clear
echo "Partition Inspection"
echo "--------------------"
echo

blkid "$part"
echo

fstype=$(blkid -o value -s TYPE "$part")

echo "Filesystem Type: $fstype"
echo

if [[ "$fstype" == ext* ]]; then

bad=$(dumpe2fs "$part" 2>/dev/null | awk '/Bad blocks:/ {print $3}')

[[ -z "$bad" ]] && echo "Bad Blocks: none recorded" || echo "Bad Blocks: $bad"

else

echo "Filesystem does not track bad blocks."

fi

echo
echo "1) Run full surface scan (slow)"
echo
echo "b) Back   h) Home   q) Quit"
echo

read -rp "Selection: " opt

case "$opt" in

1)
clear
badblocks -sv "$part"
read -p "Press ENTER..."
;;

b) return ;;
h) stage1_menu ;;
q) exit ;;
*) continue ;;

esac

done
}

##############################################
# SMART details
##############################################

stage3_smart() {

disk="$1"

clear
echo "SMART Detailed Report"
echo "---------------------"
echo

if [[ "$SMART_AVAILABLE" -eq 1 ]]; then
smartctl -a "$disk"
else
echo "SMART tools unavailable."
fi

echo
read -p "Press ENTER..."

}

##############################################
# Stage 2 Disk Overview
##############################################

stage2_menu() {

disk="$1"
dev=$(basename "$disk")

while true; do

clear
echo "Disk Overview: $disk"
echo "--------------------------"
echo

echo "Hardware Information"

[[ -f /sys/block/$dev/device/vendor ]] && echo "Vendor: $(cat /sys/block/$dev/device/vendor)"
[[ -f /sys/block/$dev/device/model ]] && echo "Model: $(cat /sys/block/$dev/device/model)"

echo
echo "Partition Layout"

lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT "$disk"

echo
echo "Filesystem Usage"

df -hT | awk 'NR==1 || /^\/dev/'

echo
echo "SMART Summary"

if [[ "$SMART_AVAILABLE" -eq 1 ]]; then
smartctl -H "$disk" 2>/dev/null | grep -i SMART
fi

echo
echo "Diagnostics"
echo

echo "0) SMART Details"

mapfile -t PARTS < <(lsblk -ln "$disk" | awk '{print $1}' | grep -v "^$dev$")

i=1
for p in "${PARTS[@]}"; do
echo "$i) Partition $i Information (/dev/$p)"
((i++))
done

echo
echo "b) Back   h) Home   q) Quit"
echo

read -rp "Selection: " opt

case "$opt" in

0)
stage3_smart "$disk"
;;

b)
return
;;

h)
stage1_menu
;;

q)
exit
;;

*)

if [[ "$opt" =~ ^[0-9]+$ ]]; then

index=$((opt-1))

if [[ $index -ge 0 && $index -lt ${#PARTS[@]} ]]; then
stage3_partition "/dev/${PARTS[$index]}"
fi

fi
;;

esac

done
}

##############################################
# Stage 1
##############################################

stage1_menu() {

while true; do

clear
echo "DiskProbe - Storage Devices"
echo "---------------------------"
echo

for i in "${!DISKS[@]}"; do

dev=${DISKS[$i]%%|*}
label=${DISKS[$i]#*|}

printf "%2d) %-12s %s\n" "$((i+1))" "$dev" "$label"

done

echo
echo "l) LVM Volumes"
echo "r) RAID Arrays"
echo "t) Storage Topology"
echo
echo "q) Quit"
echo

read -rp "Selection: " choice

case "$choice" in

q) exit ;;
l) lvm_menu ;;
r) raid_menu ;;
t) topology_view ;;

*)

if [[ "$choice" =~ ^[0-9]+$ ]] &&
((choice >=1 && choice <= ${#DISKS[@]})); then

disk=${DISKS[$((choice-1))]%%|*}
stage2_menu "$disk"

fi
;;

esac

done
}

##############################################
# MAIN
##############################################

main() {

clear
check_smart
discover_disks
disk_health_dashboard
stage1_menu

}

main
