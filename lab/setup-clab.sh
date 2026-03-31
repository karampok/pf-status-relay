#!/usr/bin/env bash
set -euo pipefail

sudo ip link add br0 type bridge || true
sudo ip link set br0 up

cat > /tmp/pf-relay-clab.yml <<'EOF'
name: pf-relay-lacp

topology:
  nodes:
    srl:
      kind: nokia_srlinux
      image: ghcr.io/nokia/srlinux:latest
      startup-config: /tmp/srl-startup.cfg
    br0:
      kind: bridge

  links:
    - endpoints: ["srl:e1-1", "br0:eth1"]
EOF

cat > /tmp/srl-startup.cfg <<'EOF'
set / interface ethernet-1/1 admin-state enable
set / interface ethernet-1/1 description "Connection to vtap0 (VM PF)"
set / interface ethernet-1/1 ethernet aggregate-id lag1

set / interface lag1 admin-state enable
set / interface lag1 description "LACP LAG to VM"
set / interface lag1 lag lag-type lacp
set / interface lag1 lag lacp interval FAST
set / interface lag1 lag lacp lacp-mode ACTIVE
set / interface lag1 lag lacp admin-key 1
set / interface lag1 lag lacp system-id-mac 00:00:00:00:00:01
set / interface lag1 lag lacp system-priority 100

set / interface lag1 subinterface 0 admin-state enable
set / interface lag1 subinterface 0 type bridged
set / interface lag1 subinterface 0 vlan encap untagged
EOF

sudo containerlab deploy -t /tmp/pf-relay-clab.yml
