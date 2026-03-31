#!/usr/bin/env bash
set -euo pipefail

virsh destroy node 2>/dev/null || true
virsh shutdown switch 2>/dev/null || true
virsh undefine node 2>/dev/null || true
virsh undefine switch 2>/dev/null || true
rm -f /var/lib/libvirt/images/node.qcow2
rm -f /var/lib/libvirt/images/switch.qcow2
