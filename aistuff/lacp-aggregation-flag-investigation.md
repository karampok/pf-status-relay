# LACP Aggregation Flag Investigation

## Investigation Summary

Research into whether production network switches clear the LACP Aggregation flag (bit 2) in single-port
LACP configurations, similar to the behavior observed in Open vSwitch (OVS).

**Date**: 2025-11-21
**Context**: pf-status-relay code fails with OVS single-port LACP reporting state 59 instead of expected
60+

## LACP Actor State Bit Field Structure

Based on IEEE 802.1AX and vendor documentation:

```
Bit 0 (0x01): LACP_ACTIVITY      - Active(1) vs Passive(0)
Bit 1 (0x02): LACP_TIMEOUT       - Fast(1) vs Slow(0)
Bit 2 (0x04): LACP_AGGREGATION   - Aggregatable(1) vs Individual(0)
Bit 3 (0x08): LACP_SYNCHRONIZATION - In Sync(1) vs Out of Sync(0)
Bit 4 (0x10): LACP_COLLECTING    - Receiving frames(1)
Bit 5 (0x20): LACP_DISTRIBUTING  - Transmitting frames(1)
Bit 6 (0x40): LACP_DEFAULTED     - Partner info defaulted(1)
Bit 7 (0x80): LACP_EXPIRED       - Actor in expired state(1)
```

**Operational link** = Bits 3+4+5 set = value 56 minimum
**Typical working link** = Bits 2+3+4+5 set = value 60 minimum

## Aggregation Flag Semantics

**Set (1)**: Port is "Aggregatable" - capable of being part of a LAG
**Cleared (0)**: Port is "Individual" - operates as standalone link

**Key Finding**: The Aggregation flag indicates *capability* to aggregate, not current aggregation
status.

## Production Switch Behavior

### Cisco Switches

**Configuration**: Single-member port-channel with LACP
**Aggregation Flag**: **ALWAYS SET** (value 4 present)
**Typical State**: 0x3D or 0x3F in hexadecimal

Even with a single member, Cisco sets the Aggregation flag because the port is configured in a
port-channel (aggregation group), even if that group has only one member.

**Sources**:
- Cisco LACP documentation: https://www.cisco.com/c/en/us/td/docs/ios/12_2sb/feature/guide/gigeth.html
- LACP troubleshooting guide:
  https://www.cisco.com/c/en/us/support/docs/lan-switching/link-aggregation-control-protocol-lacp-8023ad/221051-troubleshoot-link-aggregation-control-pr.html

### Juniper Switches

**Configuration**: Aggregated Ethernet (ae) interface with `minimum-links 1`
**Aggregation Flag**: **ALWAYS SET**
**Output**: `show lacp interfaces` displays "Aggr: Yes" even for single-member AE

Juniper explicitly supports single-member aggregated ethernet interfaces:
```
set chassis aggregated-devices ethernet device-count 1
set interfaces ge-0/0/0 ether-options 802.3ad ae0
set interfaces ae0 aggregated-ether-options minimum-links 1
set interfaces ae0 aggregated-ether-options lacp active
set interfaces ae0 aggregated-ether-options lacp periodic fast
```

**Rationale**: Port is configured for 802.3ad mode, therefore "aggregatable"

**Sources**:
- https://www.juniper.net/documentation/us/en/software/junos/interfaces-ethernet-switches/topics/topic-map/switches-interface-aggregated.html
- Configuration examples show `minimum-links 1` as valid parameter

### Arista Switches

**Configuration**: Port-channel with LACP
**Aggregation Flag**: **SET** in normal operation
**Special Mode**: LACP fallback individual

Arista has "LACP fallback individual" mode where ports temporarily enter "Individual" state during:
- Server boot (before LACP negotiates)
- LACP timeout conditions

**Key Distinction**: This is a **transient state**, not steady-state. Once LACP PDU is received, ports
immediately revert to normal aggregated mode with Aggregation flag set.

**Purpose**: Allow traffic flow during boot/failover, not for long-term single-port operation

**Sources**:
- Arista EOS documentation on port-channels and LACP
- Community article: Configuring LACP Fallback Individual Ports

### HP/HPE Comware (Aruba)

**Feature**: `lacp edge-port` configuration
**Behavior**: Similar to Arista fallback - ports in "Individual" state show flag "{AG}"

Member ports initially placed in Individual state when no LACP traffic received or peer times out.
Ports in individual state forward traffic but continue sending LACP PDUs.

**Key**: This is for **boot-time behavior**, not steady-state single-port LACP

**Source**: https://abouthpnetworking.com/2014/12/13/comware-link-aggregation-lacp-edge-port/

### Linux Kernel Bonding (802.3ad mode)

**Aggregation Flag**: **ALWAYS SET** (AD_STATE_AGGREGATION = 0x4)
**Typical State**: 63 when fully operational (all flags except Expired/Defaulted)

Linux bonding driver sets aggregation bit throughout LACP negotiation, even with single slave.

**Source**: https://hareshkhandelwal.blog/2022/07/28/lets-understand-lacp-state-machine-using-linux-bond/

## Virtual/Software Switch Behavior

### Open vSwitch (OVS)

**Observed Behavior**: Reports state **59** (missing Aggregation bit) for single-port bonds
**Configuration**: Single port with `lacp=active`

Example from `hack/virt-test.sh`:
```bash
ovs-vsctl add-port ovsbr0 vtap0 -- set port vtap0 lacp=active other_config:lacp-time=fast
```

**Actor State**: 63 (includes Aggregation)
**Partner State**: 59 (missing Aggregation, value 56 = Sync+Collecting+Distributing only)

**Rationale**: OVS interprets "not actually aggregated" as "should not set Aggregatable flag"

This behavior appears **unique to OVS** among all implementations researched.

### Other Virtual Switches

No evidence found for:
- VMware vSwitch LACP behavior
- Linux bridge with LACP
- Other hypervisor virtual switches

Would require testing to confirm behavior.

## IEEE 802.1AX Standard Interpretation

**Standard Position**: Aggregation flag set = "port may include more than one physical port"
**Aggregation flag cleared** = "Individual link"

The standard allows both interpretations:
1. **Configuration-based**: Port configured for aggregation = flag set (Cisco, Juniper, Linux)
2. **State-based**: Port actually aggregated = flag set (OVS interpretation)

Both are **technically valid** per specification.

## Production Use Cases for Single-Port LACP

Legitimate production scenarios:

1. **Migration/Phased Deployment**: Start with one link, add second later without reconfiguration
2. **Protocol-based Monitoring**: LACP PDU exchange provides faster failure detection than physical
   layer
3. **Switch Policy Enforcement**: Some datacenter switches require LACP even for single uplinks
4. **Future-Proofing**: Infrastructure ready for additional links when capacity needed
5. **Testing/Development**: Virtual environments without physical hardware

## Conclusion

### Physical/Production Switches: **NO EVIDENCE** of Aggregation Flag Clearing

**All production switches researched** (Cisco, Juniper, Arista, HP Comware) **SET the Aggregation
flag** even for single-member LAGs in steady-state operation.

**Fallback/Edge-port modes** (Arista, HP) use Individual state only as **transient behavior** during
boot/timeout, not as steady-state configuration.

### Virtual Switches: **OVS is the Outlier**

**Open vSwitch** appears to be the **only implementation** that clears the Aggregation flag for
single-port LACP configurations in steady-state operation.

### Impact on pf-status-relay Code

**Current Code** (`pkg/lacp/flags/flags.go:27`):
```go
if (a & (Distributing | Collecting | Synchronization | Aggregation)) != 60 {
    return false
}
```

**Works with**:
- ✓ All production switches (Cisco, Juniper, Arista, HP)
- ✓ Linux kernel bonding
- ✓ No-name switches (likely follow Cisco/standard behavior)

**Fails with**:
- ✗ OVS single-port LACP (virtual test environments)
- ✗ Potentially other virtual switch implementations

**Recommended Fix**:
```go
requiredFlags := Distributing | Collecting | Synchronization  // Value 56
if (a & requiredFlags) != requiredFlags {
    return false
}
```

**Fix Validation**:
- ✓ Accepts state 60+: Production switches with Aggregation SET
- ✓ Accepts state 56-59: OVS virtual environments with Aggregation CLEAR
- ✓ Maintains safety: Still requires operational flags (Sync+Collecting+Distributing)
- ✓ No false positives: Won't accept links missing forwarding capability

### Operational Flags Are What Matter

The truly critical flags for link operation are:
- **Synchronization** (bit 3): Partners are in sync
- **Collecting** (bit 4): Can receive frames
- **Distributing** (bit 5): Can transmit frames

Combined value: **56** = Link is operational and forwarding traffic

The Aggregation flag (bit 2, value 4) indicates *configuration/capability*, not *operational status*.

## References

### Standards
- IEEE 802.1AX-2020 (Link Aggregation)
- IEEE 802.3ad (LACP, now part of 802.1AX)

### Vendor Documentation
- Cisco LACP Configuration Guide
- Juniper Aggregated Ethernet Interfaces Overview
- Arista EOS Port Channels and LACP
- HP Comware Link Aggregation

### Technical Articles
- Decoding LACP Port State: https://movingpackets.net/2017/10/17/decoding-lacp-port-state/
- Understanding LACP State Machine (Linux):
  https://hareshkhandelwal.blog/2022/07/28/lets-understand-lacp-state-machine-using-linux-bond/
- Linux Kernel Bonding Documentation: https://docs.kernel.org/networking/bonding.html
- OVS Bonding Documentation: https://docs.openvswitch.org/en/latest/topics/bonding/

## Test Environment

Virtual test environment using OVS (`hack/virt-test.sh`):
- QEMU/KVM VM with SR-IOV emulated NIC (Intel igb)
- Single tap interface (`vtap0`) configured with LACP active
- OVS bridge with LACP system-id configured
- Reproduces the state 59 behavior

This environment validates the fix works with OVS single-port LACP configurations.
