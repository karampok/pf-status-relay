# CLAUDE.md

## Project Overview

LACP Status Monitor and Relay for SR-IOV Interfaces. This application monitors
LACP (Link Aggregation Control Protocol) status on Physical Functions (PFs) and
relays status by adjusting link state of associated Virtual Functions (VFs).

**Purpose**: Prevents networking "black holes" where a virtual machine using a
VF believes its link is up, even though the underlying physical LACP bond has
failed. When LACP is down, VFs are set to "disable" state to force failover;
when LACP is up, VFs are set to "auto" state to enable traffic.

## Go Version

- Go version: 1.23.0
- Toolchain: go1.24.1
- Read `go.mod` before making changes to understand current dependencies

## Build and Development Commands

### Build
```bash
make build              # Build binary using hack/build.sh produces: `bin/pf-status-relay`
make test-unit          # Run all unit tests with Ginkgo
go test -v ./pkg/lacp/... -count=1  # Run tests for specific package
make image-build        # Build container image (default: localhost:5000/pf-status-relay:latest)
make image-build IMAGE_REGISTRY=quay.io/<user> IMAGE_TAG=latest
podman push quay.io/<user>/pf-status-relay:latest
```
Makefile variables: `IMAGE_REGISTRY` (default: localhost:5000), `IMAGE_NAME` (default: pf-status-relay), `IMAGE_TAG` (default: latest), `OCI_BIN` (default: docker)

### CI/CD

`.github/workflows/test.yml` runs on push/PR to main:
- **lint**: golangci-lint with `-v` flag, skip-cache enabled
- **build**: Cross-compile for linux/amd64, linux/arm64, linux/ppc64le
- **test**: Run unit tests on linux/amd64

## Code

**Entry Point** (`cmd/pf-status-relay.go`): Reads config from env vars
(`PF_STATUS_RELAY_INTERFACES`, `PF_STATUS_RELAY_POLLING_INTERVAL`), spawns 3
goroutines, handles SIGINT/SIGTERM.

**Three Concurrent Goroutines**:
- **Inspect** (`pkg/lacp`): Validates PFs have 802.3ad bond master, processes
  netlink events from queue, updates PF "Ready" state
- **Monitor** (`pkg/lacp`): Polls LACP status every interval, reads
  `BondSlave.AdActorOperPortState` (8-bit flag, value 60 = operational), sets
  VF states
- **Subscribe** (`pkg/subscribe`): Listens to netlink events, pushes PF
  indexes to queue

**LACP Detection**: Checks `BondSlave.AdActorOperPortState` bitmask for
`SYNCHRONIZATION`, `COLLECTING`, `DISTRIBUTING` flags (combined value: 60 =
link operational).

**State-Change Driven**: Actions only on transitions (`p.ProtoState != pf.Up`)
to prevent log spam.

**VF Link State Control**:
- LACP UP → Set VFs to `VF_LINK_STATE_AUTO` (enable traffic)
- LACP DOWN → Set VFs to `VF_LINK_STATE_DISABLE` (force failover)

**Key Files**:
- `pkg/lacp/pf/pf.go`: PF struct with mutex-protected state
- `pkg/lacp/flags/flags.go`: `IsProtocolUp()` checks LACP flags
- Uses `vishvananda/netlink` for all kernel communication

**Testing**: Uses Ginkgo framework with `suite_test.go` pattern. Specs use dot
imports for Ginkgo/Gomega. Mock netlink operations using `go.uber.org/mock`.
Mock generated with: `mockgen -source=pkg/interfaces/interfaces.go
-package=interfaces`

## Important Notes
- PFs must be in 802.3ad bond mode with single slave

## Virtual Testing with OVS/libvirt

`hack/virt-test.sh` creates virtual environment with Open vSwitch and KVM for testing.

**SR-IOV Emulation Support**: QEMU igb device (Intel 82576) supports SR-IOV emulation since QEMU 8.0/libvirt 9.3 (2023). Can create virtual VFs without physical hardware for testing VF link state control.

**Before running the script, check prerequisites and warn user about missing items:**

Check required packages:
```bash
for pkg in ovs-vsctl qemu-system-x86_64 virsh virt-install virt-customize virt-copy-in; do
  command -v $pkg >/dev/null 2>&1 || echo "Missing: $pkg"
done
```

Check versions for SR-IOV support (requires QEMU 8.0+, libvirt 9.3+):
```bash
qemu-system-x86_64 --version
virsh --version
```

Check group membership (use `groups` command - works with traditional and systemd-homed users):
```bash
for grp in libvirt kvm; do
  groups | grep -qw $grp || echo "User not in group: $grp"
done
```

Note: On Fedora, also check for `openvswitch` or `hugetlbfs` group for non-root OVS access. On Arch, OVS typically requires starting the systemd service.

If packages are missing, inform the user with appropriate install commands:
- Arch: `yay -S openvswitch qemu-full libvirt virt-install libguestfs guestfs-tools`
- Fedora: `sudo dnf install openvswitch qemu-kvm libvirt virt-install libguestfs-tools`

Note: On Arch, `virt-customize` is in the `guestfs-tools` package, while `virt-copy-in` is in `libguestfs`.

For group membership, detect if user is systemd-homed managed:
```bash
homectl inspect $USER >/dev/null 2>&1 && echo "systemd-homed" || echo "traditional"
```

Add groups (adjust list based on what's missing):
- Traditional users: `sudo usermod -aG libvirt,kvm $USER`
- systemd-homed users: `sudo homectl update $USER --member-of=$(homectl inspect $USER --json=short | jq -r '.memberOf[]' | paste -sd,),libvirt,kvm`

Note: After adding groups, logout/login required for changes to take effect.
