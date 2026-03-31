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
