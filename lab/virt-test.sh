#!/usr/bin/env bash
set -euo pipefail

# Prerequisites (Arch Linux):
#   yay -S openvswitch qemu-full libvirt virt-install libguestfs guestfs-tools
#   sudo usermod -aG libvirt,kvm $USER
#   sudo systemctl enable --now libvirtd ovs-vswitchd
#
# NOTE: Requires system mode (qemu:///system) for OVS bridge support
# Session mode (qemu:///session) does NOT support OVS bridges

make build

cat > bin/net-vm-setup.sh <<'EOF'
#!/bin/bash
set -euo pipefail
dmesg -n 3
nmcli con add type bond ifname bond0 mode 802.3ad
nmcli con mod bond-bond0 bond.options mode=802.3ad,lacp_rate=fast
nmcli con add type ethernet ifname enp7s0 master bond0
nmcli con up bond-slave-enp7s0
echo 2 > /sys/class/net/enp7s0/device/sriov_numvfs
cat /proc/net/bonding/bond0
ip link show enp7s0
EOF

cat > bin/virt-clean.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

virsh destroy pf-relay-test 2>/dev/null || true
virsh undefine pf-relay-test 2>/dev/null || true
rm -f /var/lib/libvirt/images/pf-relay-test.qcow2
ovs-vsctl del-br ovsbr0 2>/dev/null || true
EOF
chmod +x bin/virt-clean.sh

cat > bin/setup-vm.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ -f ./rhel10-guest-image.qcow2 ]] || curl -L -o ./rhel10-guest-image.qcow2 \
  http://download.eng.bos.redhat.com/released/RHEL-10/10.1/BaseOS/x86_64/images/rhel-guest-image-10.1-20251021.0.x86_64.qcow2

rm -f /var/lib/libvirt/images/pf-relay-test.qcow2
qemu-img create -f qcow2 /var/lib/libvirt/images/pf-relay-test.qcow2 15G
virt-resize --expand /dev/sda3 ./rhel10-guest-image.qcow2 /var/lib/libvirt/images/pf-relay-test.qcow2

virt-customize -a /var/lib/libvirt/images/pf-relay-test.qcow2 \
  --root-password password:redhat --run-command 'yum remove -y cloud-init' \
  --copy-in bin/pf-status-relay:/root  --chmod 0755:/root/pf-status-relay \
  --copy-in bin/net-vm-setup.sh:/root --chmod 0755:/root/net-vm-setup.sh

cat > /tmp/iface1.xml <<'INNER_EOF'
<interface type='ethernet'>
  <target dev='vtap0'/>
  <model type='igb'/>
  <address type='pci' domain='0x0000' bus='0x07' slot='0x00' function='0x0'/>
</interface>
INNER_EOF

virt-install \
  --connect qemu:///system \
  --name pf-relay-test \
  --memory 4096 --vcpus 2 \
  --disk /var/lib/libvirt/images/pf-relay-test.qcow2,bus=virtio \
  --network none \
  --osinfo rhel10.0 \
  --import --noautoconsole --graphics none --console pty,target_type=serial

virsh --connect qemu:///system attach-device pf-relay-test /tmp/iface1.xml --config --live
EOF
chmod +x bin/setup-vm.sh

cat > bin/setup-lacp.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ovs-vsctl --may-exist add-br ovsbr0
ip link set ovsbr0 up
ovs-vsctl set bridge ovsbr0 other-config:lacp-system-id=00:11:22:33:44:55

ovs-vsctl add-port ovsbr0 vtap0 -- set port vtap0 lacp=active other_config:lacp-time=fast

ovs-vsctl show
ovs-vsctl list port vtap0
ovs-appctl lacp/show vtap0
EOF
chmod +x bin/setup-lacp.sh

echo "sudo ./bin/virt-clean.sh"
echo "sudo ./bin/setup-vm.sh"
echo "sudo ./bin/setup-lacp.sh"
echo "sudo virsh console pf-relay-test"
echo "/usr/local/bin/net-vm-setup.sh"
echo ""

# Show status
# echo "PF_STATUS_RELAY_INTERFACES=eth0 PF_STATUS_RELAY_POLLING_INTERVAL=500 /usr/local/bin/pf-status-relay"
# echo ""
# echo "=== Check Status ==="
# echo "Bond status: cat /proc/net/bonding/bond0"
# echo "VF status: ip link show eth0"
# echo ""
# echo "=== Test LACP (from host) ==="
# echo "sudo ovs-vsctl set port bond-vm lacp=off   # LACP DOWN"
# echo "sudo ovs-vsctl set port bond-vm lacp=active # LACP UP"
