# LACP Aggregation Flag Fix

## Problem

The pf-status-relay incorrectly reports LACP as DOWN when negotiating with
single-port LACP partners (e.g., OVS single-port bonds). The issue is in
`pkg/lacp/flags/flags.go:27` which checks for an exact bitmask match of 60,
requiring all four flags: Synchronization, Aggregation, Collecting, and
Distributing.

## Root Cause

Single-port LACP configurations don't set the **Aggregation flag** (bit 2)
because aggregation implies multiple ports bundled together. When OVS operates
with a single port (`vtap0`) in LACP mode, it negotiates the protocol
successfully but the partner port state is 59 (missing Aggregation bit) instead
of the expected 60 or higher.

Example from testing:
- Actor port state: 63 (all flags set including Activity)
- Partner port state: 59 (missing Aggregation flag, value 4)
- Current check: `(59 & 60) != 60` → fails because result is 58

## Why Single-Port LACP is Valid

Single-port LACP is a legitimate configuration used for:
- Protocol-based link monitoring without actual aggregation
- Automated failover detection at L2 level
- Switch port policy enforcement (some switches require LACP even for single
  uplinks)

The LACP standard (IEEE 802.1AX) allows single-port aggregation groups. The
critical operational flags are Synchronization, Collecting, and Distributing -
these indicate the link is forwarding traffic. The Aggregation flag only
indicates the port *can* be aggregated, not that it *must* be.

## Proposed Fix

Change the check from exact match to mask-based validation of required flags:

```go
requiredFlags := Distributing | Collecting | Synchronization
if (a & requiredFlags) != requiredFlags {
    return false
}
```

This validates that the essential forwarding flags are set while allowing
Aggregation to be optional, supporting both multi-port LAGs and single-port
LACP scenarios.
