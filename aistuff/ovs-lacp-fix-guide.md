# How to Fix LACP Aggregation Flag in Open vSwitch

## Problem Summary

Open vSwitch (OVS) incorrectly clears the LACP Aggregation flag (LACP_STATE_AGG) for single-port LACP
bonds, causing interoperability issues with some production switches and violating the IEEE 802.1AX
standard interpretation used by other implementations.

**Current OVS behavior**: Aggregation flag cleared (state 59) for single-port bonds
**Expected behavior**: Aggregation flag set (state 60+) even for single-port bonds
**Affected code**: `lib/lacp.c` in the openvswitch/ovs repository

## Evidence This is a Bug

1. **libteam fixed the same bug**: https://github.com/jpirko/libteam/issues/15
   - Single-port teams had Aggregation flag cleared
   - Caused traffic failures on Juniper switches
   - Was fixed as a bug

2. **iPXE had to patch it**: https://lists.ipxe.org/pipermail/ipxe-devel/2014-July/003659.html
   - Dell PowerConnect switches required Aggregation flag set
   - Without it, "frames would not pass"

3. **All vendors set the flag**: Cisco, Juniper, Arista, HP all set Aggregation flag for
   single-member LAGs

4. **IEEE 802.1AX interpretation**: "may include more than one port" means capability, not current
   state

## The Fix

### Code History

**Original author**: Ethan Jackson <ethan@nicira.com>
**Original commit**: 6aa743082 (2011-02-28) - "vswitchd: Modularize LACP"
**Bug introduced**: In the original implementation (has been wrong since 2011)
**Most recent change**: 9e56549c2 (2022-03-23) by Adrian Moreno <amorenoz@redhat.com>

The `> 1` logic has been present since the LACP module was first introduced in 2011. This means the
bug has existed for **14 years**.

**Top contributors to lib/lacp.c**:
- Ethan Jackson (31 commits) - Original author
- Ben Pfaff (23 commits) - Emeritus maintainer
- Huanle Han (5 commits)

### Location

**Repository**: https://github.com/openvswitch/ovs
**File**: `lib/lacp.c`
**Function**: `member_get_actor()` (originally `slave_get_actor()` before terminology change)

### Current Code (Problematic)

```c
if (hmap_count(&lacp->members) > 1) {
    state |= LACP_STATE_AGG;
}
```

This sets the Aggregation flag **only** if there are 2+ members.

### Proposed Fix

```c
if (hmap_count(&lacp->members) > 0) {
    state |= LACP_STATE_AGG;
}
```

**Rationale**: If the port is in an LACP bond (even with 1 member), it's configured for aggregation
(aggregatable), so the flag should be set.

**Alternative fix** (more explicit):

```c
/* Set aggregation flag if port is part of LACP bond.
 * Per IEEE 802.1AX, the flag indicates capability to aggregate,
 * not current aggregation status. Even single-port bonds are
 * configured for aggregation and should advertise this capability.
 */
if (hmap_count(&lacp->members) >= 1) {
    state |= LACP_STATE_AGG;
}
```

Or simply always set it since we're in LACP context:

```c
/* Always set aggregation flag in LACP mode.
 * If we're using LACP, the port is by definition aggregatable.
 */
state |= LACP_STATE_AGG;
```

## How to Submit the Fix to OVS

### Important: OVS Does NOT Use GitHub Pull Requests

OVS uses an **email-based patch workflow** similar to the Linux kernel.

### Step-by-Step Process

#### 1. Set Up Development Environment

```bash
# Clone the repository
git clone https://github.com/openvswitch/ovs.git
cd ovs

# Build and test
./boot.sh
./configure
make
make check
```

#### 2. Make Your Changes

Edit `lib/lacp.c` and make the fix described above.

Also check if tests need updating:
- `tests/lacp.at` - LACP test suite

#### 3. Write Tests

Add test cases to verify:
- Single-port LACP bond sets Aggregation flag
- State value is 60+ (not 59) for operational single-port bonds

#### 4. Verify Your Fix

```bash
# Run all tests
make check

# Run LACP-specific tests
make check TESTSUITEFLAGS='-k lacp'

# Check coding style
utilities/checkpatch.py -1
```

#### 5. Create Commit with Proper Message

```bash
git add lib/lacp.c tests/lacp.at
git commit
```

**Commit message format**:

```
lacp: Set aggregation flag for single-member bonds

The current implementation only sets the LACP_STATE_AGG flag when
hmap_count(&lacp->members) > 1, causing single-port LACP bonds to
advertise themselves as "Individual" rather than "Aggregatable".

This causes interoperability issues:
- Some switches (e.g., Dell PowerConnect, Juniper) require the
  aggregation flag to be set even for single-member LAGs
- This behavior is inconsistent with other LACP implementations
  (Linux bonding, Cisco, Juniper, Arista)
- The IEEE 802.1AX standard states the flag indicates a port "may
  include more than one physical port" (capability), not that it
  currently does (state)

The libteam project fixed the identical issue:
https://github.com/jpirko/libteam/issues/15

Change the condition from > 1 to > 0 (or always set the flag in
LACP context) to indicate the port is configured for aggregation.

Reported-by: <your-name> <your-email>
Signed-off-by: <your-name> <your-email>
```

#### 6. Generate Patch Email

```bash
# For a single patch
git format-patch -1 --to=dev@openvswitch.org

# This creates a .patch file
```

#### 7. Send Patch to Mailing List

**Mailing List**: dev@openvswitch.org

```bash
# Send the patch
git send-email --to=dev@openvswitch.org <patch-file>.patch
```

**Alternative** (manual email):

1. Open the .patch file
2. Copy the entire contents
3. Send email to dev@openvswitch.org
4. Paste patch as plain text (not HTML)
5. Subject: [PATCH] lacp: Set aggregation flag for single-member bonds

#### 8. Track Your Patch

Your patch will be tracked on **Patchwork**:
https://patchwork.ozlabs.org/project/openvswitch/list/

#### 9. Respond to Review Comments

- OVS maintainers will review on the mailing list
- Respond to comments via email
- If changes needed, send v2, v3, etc.:
  ```bash
  git format-patch -1 --to=dev@openvswitch.org -v2
  ```

### Required DCO Sign-off

All commits must include:

```
Signed-off-by: Your Name <your.email@example.com>
```

This certifies you have the right to submit the patch under the project's license.

## Testing Your Fix

### Manual Testing with Virtual Environment

Use the `hack/virt-test.sh` script from pf-status-relay:

1. Build OVS from your patched source
2. Install patched OVS
3. Run the virtual test setup
4. Verify partner state now shows 60+ instead of 59

### Expected Results After Fix

**Before fix**:
- Actor state: 63 (includes Aggregation)
- Partner state: 59 (missing Aggregation)

**After fix**:
- Actor state: 63 (includes Aggregation)
- Partner state: 60+ (includes Aggregation)

## Additional Considerations

### Backward Compatibility

This change should not break existing deployments:
- Setting the flag makes OVS more compatible with production switches
- Partners expecting flag cleared would ignore it (informational flag)
- No behavioral change in OVS forwarding logic, only in advertised state

### Documentation Updates

Consider updating:
- `Documentation/topics/bonding.rst` - LACP bonding documentation
- Release notes mentioning the fix

### Related Code to Review

Check if similar logic exists elsewhere:
```bash
git grep "hmap_count.*members.*>" lib/
git grep "LACP_STATE_AGG" lib/
```

## References

### OVS Development Resources

- **Contributing Guide**: https://docs.openvswitch.org/en/latest/internals/contributing/
- **Submitting Patches**: https://docs.openvswitch.org/en/latest/internals/contributing/submitting-patches/
- **Mailing List**: dev@openvswitch.org
- **Mailing List Archive**: https://mail.openvswitch.org/pipermail/ovs-dev/
- **Patchwork**: https://patchwork.ozlabs.org/project/openvswitch/list/
- **GitHub Mirror**: https://github.com/openvswitch/ovs (read-only, for reference)

### Standards and Bug Reports

- IEEE 802.1AX-2020 (Link Aggregation standard)
- libteam bug: https://github.com/jpirko/libteam/issues/15
- iPXE patch: https://lists.ipxe.org/pipermail/ipxe-devel/2014-July/003659.html

## Alternative: Report as Bug First

If you're not comfortable submitting a patch, you can report the issue:

1. Send email to dev@openvswitch.org with subject: "[BUG] LACP aggregation flag not set for
   single-member bonds"
2. Describe the issue with evidence
3. Reference libteam bug and iPXE patch
4. Explain interoperability problems

Someone from the OVS team may pick it up and fix it.

## Current OVS Maintainers

These maintainers will likely review your patch:

**Active Maintainers** (as of 2024):
- Aaron Conole <aconole@redhat.com>
- Alin Serdean <aserdean@ovn.org>
- Ansis Atteka <ansisatteka@gmail.com>
- Eelco Chaudron <echaudro@redhat.com>
- Ian Stokes <istokes@ovn.org>
- Ilya Maximets <i.maximets@ovn.org>
- Kevin Traynor <ktraynor@redhat.com>
- Simon Horman <horms@ovn.org>
- William Tu <u9012063@gmail.com>

**Emeritus Maintainers** (may still participate in reviews):
- Ben Pfaff <blp@ovn.org> (23 commits to lacp.c)
- Ethan Jackson <ejj@eecs.berkeley.edu> (31 commits to lacp.c, original author)

**Note**: You don't need to CC specific maintainers - sending to dev@openvswitch.org is sufficient.

## Contact

- **Mailing list**: dev@openvswitch.org (subscribe at http://openvswitch.org/support/)
- **IRC**: #openvswitch on OFTC
- **Slack**: openvswitch.slack.com

## Timeline Expectations

- Patch review: Days to weeks
- Acceptance: Can vary based on discussion
- Release: Next OVS release cycle
- Backport: May be backported to LTS branches if deemed important

For production environments, you may need to build and deploy patched OVS locally while waiting for
official release.
