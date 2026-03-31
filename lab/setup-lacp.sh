#!/usr/bin/env bash
set -euo pipefail

ovs-vsctl --may-exist add-br ovsbr0
ip link set ovsbr0 up
ovs-vsctl set bridge ovsbr0 other-config:lacp-system-id=00:11:22:33:44:55

ovs-vsctl add-port ovsbr0 vtap0 -- set port vtap0 lacp=active other_config:lacp-time=fast

ovs-vsctl show
ovs-vsctl list port vtap0
ovs-appctl lacp/show vtap0
