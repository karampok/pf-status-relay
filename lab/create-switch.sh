#!/usr/bin/env bash
set -euo pipefail

echo "Copying vJunos-switch image..."
#https://www.juniper.net/documentation/us/en/software/vjunos/vjunos-switch-kvm/topics/deploy-and-manage-vjunos-switch-onkvm.html

# Copy vJunos-switch image to libvirt images directory
if [ ! -f "vJunos-switch-25.2R1.9.qcow2" ]; then
    echo "ERROR: vJunos-switch-25.2R1.9.qcow2 not found in current directory"
    exit 1
fi

cp vJunos-switch-25.2R1.9.qcow2 /var/lib/libvirt/images/switch.qcow2

echo "Creating Linux bridges for vJunos-switch interfaces..."

# Create bridges for ge-0/0/0 and ge-0/0/1
ip link add ge-000 type bridge 2>/dev/null || echo "Bridge ge-000 already exists"
ip link add ge-001 type bridge 2>/dev/null || echo "Bridge ge-001 already exists"
ip link set ge-000 up
ip link set ge-001 up

echo "Creating switch configuration disk..."

# Check if make-config.sh exists
if [ ! -f "make-config.sh" ]; then
    echo "ERROR: make-config.sh not found in current directory"
    echo ""
    echo "Please download make-config.sh from Juniper vJunos Lab Software Downloads:"
    echo "  https://support.juniper.net/support/downloads/"
    echo ""
    echo "Look for 'make-config-*.sh' (e.g., make-config-23.2R1.14.sh)"
    echo "and place it in the current directory as 'make-config.sh'"
    exit 1
fi

# Ensure make-config.sh is executable
chmod +x make-config.sh

# Create config disk using Juniper's script
# Note: make-config.sh creates a raw .img file, not qcow2
./make-config.sh juniper.conf /var/lib/libvirt/images/switch-config.img

echo "Creating switch VM..."
virt-install \
  --name switch \
  --memory 5120 \
  --vcpus 4,sockets=1,cores=4,threads=1 \
  --cpu IvyBridge,+vmx \
  --disk /var/lib/libvirt/images/switch.qcow2,device=disk,bus=virtio,target=vda,cache=writeback \
  --disk /var/lib/libvirt/images/switch-config.img,device=disk,bus=usb,target=sda \
  --network type=bridge,source=ge-000,model.type=virtio,mtu.size=9600,address.type=pci,address.domain=0x0000,address.bus=0x00,address.slot=0x08,address.function=0x0 \
  --network type=bridge,source=ge-001,model.type=virtio,mtu.size=9600,address.type=pci,address.domain=0x0000,address.bus=0x00,address.slot=0x09,address.function=0x0 \
  --osinfo freebsd13.0 \
  --import --noautoconsole --graphics none

echo ""
echo "VM created. Boot time: ~7 minutes"
echo ""
echo "Console access:"
echo "  virsh console switch"
echo ""
echo "Clean up:"
echo "  virsh shutdown switch"
echo "  virsh undefine switch"
