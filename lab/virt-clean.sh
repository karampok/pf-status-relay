#!/usr/bin/env bash
set -euo pipefail

virsh destroy pf-relay-test 2>/dev/null || true
virsh undefine pf-relay-test 2>/dev/null || true
rm -f /var/lib/libvirt/images/pf-relay-test.qcow2
ovs-vsctl del-br ovsbr0 2>/dev/null || true
