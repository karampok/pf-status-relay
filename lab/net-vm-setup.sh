#!/bin/bash
set -euo pipefail
nmcli con add type bond ifname bond0 mode 802.3ad
nmcli con mod bond-bond0 bond.options mode=802.3ad,lacp_rate=fast
nmcli con add type ethernet ifname enp7s0 master bond0
nmcli con up bond-slave-enp7s0
echo 2 > /sys/class/net/enp7s0/device/sriov_numvfs
cat /proc/net/bonding/bond0
ip link show enp7s0
