#!/usr/bin/env bash
set -euo pipefail

#  curl -L -o rhel10-guest-image.qcow2  http://download.eng.bos.redhat.com/released/RHEL-10/10.1/BaseOS/x86_64/images/rhel-guest-image-10.1-20251021.0.x86_64.qcow2

# curl -L -o vJunos-switch-25.2R1.9.qcow2 https://cdn.juniper.net/software/vJunos-switch/25.2R1/vJunos-switch-25.2R1.9.qcow2?SM_USER=anon&__gda__=1763731335_6ff745a122ab8dc18364281a7fec429c


cp vJunos-switch-25.2R1.9.qcow2 /var/lib/libvirt/images/switch.qcow2

# cp rhel10-guest-image.qcow2 /var/lib/libvirt/images/node.qcow2
# virt-customize -a /var/lib/libvirt/images/node.qcow2 \
#   --root-password password:redhat \
#   --run-command 'yum remove -y cloud-init'
#
virsh net-define /etc/libvirt/qemu/networks/default.xml
#virsh net-start default
virsh net-autostart default

# echo "Creating node VM..."
# virt-install \
#   --name node \
#   --memory 4096 --vcpus 2 \
#   --disk /var/lib/libvirt/images/node.qcow2,bus=virtio \
#   --network type=ethernet,target=vtap0,model=igb \
#   --osinfo rhel10.0 \
#   --import --noautoconsole --graphics none
#
echo "Creating switch VM..."
genisoimage -o /var/lib/libvirt/images/switch-config.iso \
  -V "vmm-data" \
  -r -J \
  juniper.conf

virt-install \
  --name switch \
  --memory 5120 --vcpus 4 \
  --disk /var/lib/libvirt/images/switch.qcow2 \
  --disk /var/lib/libvirt/images/switch-config.iso,device=cdrom,readonly=on \
  --network type=ethernet,target=vtap10,model=virtio \
  --network network=default,model=virtio \
  --osinfo freebsd13.0 \
  --import --noautoconsole --graphics none

echo "  virsh console node"
echo "  virsh console switch"
echo "Clean up:"
echo "  virsh destroy node"
echo "  virsh shutdown switch"
echo "  virsh undefine node switch"
