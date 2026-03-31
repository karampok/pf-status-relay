#!/bin/bash
# SR-IOV LACP Bond Test Setup Script
# This script automates the verification and setup of SR-IOV LACP bonding
# for testing the pf-status-relay operator

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Verify SR-IOV Operator Status
log_info "Step 1: Verifying SR-IOV Network Operator pods..."
oc get pods -n openshift-sriov-network-operator

# Step 2: Verify PF Status Operator Status
log_info "Step 2: Verifying PF Status Relay Operator pod..."
oc get pods -n openshift-pf-status-relay-operator

# Step 3: Verify SR-IOV Physical Interfaces on worker-0
log_info "Step 3: Checking physical interfaces connectivity on worker-0..."
log_warn "Manual step: Run the following on worker-0 node:"
echo "  ip link show ens5f0"
echo "  ip link show ens5f1"
echo "Press Enter to continue..."
read -r

# Step 4: Create LACP Bond Interfaces on worker-0
log_info "Step 4: Creating LACP bond interfaces (bond10, bond20) on worker-0..."
oc apply -f nncpBond10Worker0.yaml
oc apply -f nncpBond20Worker0.yaml

log_info "Waiting for bond configuration to apply..."
sleep 5

log_info "Verifying bond policy status..."
oc get nodenetworkconfigurationpolicies.nmstate.io

# Step 5: Configure LACP on Juniper Switch
log_info "Step 5: Configure LACP bond interfaces on lab switch..."
log_warn "Manual step: Apply Juniper switch configuration (see juniper-commands doc)"
echo "Press Enter when switch configuration is complete..."
read -r

# Step 6: Verify LACP Bond Status
log_info "Step 6: Verifying LACP bond status on node and switch..."
log_warn "Manual verification required:"
echo "On worker-0 node:"
echo "  cat /proc/net/bonding/bond10  # Look for 'port state: 63'"
echo "  cat /proc/net/bonding/bond20"
echo ""
echo "On Juniper switch:"
echo "  show lacp interfaces ae10"
echo "  show lacp interfaces ae20"
echo ""
echo "Expected: Dist Col Syn Aggr all 'Yes', port state 63"
echo "Press Enter to continue..."
read -r

# Step 7: Create SR-IOV NetworkNodePolicy for worker-1
log_info "Step 7: Creating SR-IOV NetworkNodePolicy for client pod on worker-1..."
oc apply -f sriovnetworkpolicy-client.yaml

# Step 8: Wait for cluster stability
log_info "Step 8: Waiting for cluster to reconcile network configurations..."
log_warn "Sleeping 30 seconds for stability..."
sleep 30

# Step 9: Deploy PFLACPMonitor CRD
log_info "Step 9: Deploying PFLACPMonitor custom resource..."
oc apply -f pflacpmonitor.yaml

log_info "Waiting for PFLACPMonitor pod to start..."
sleep 10

# Step 10: Verify PFLACPMonitor logs show LACP "up"
log_info "Step 10: Verifying PFLACPMonitor pod reports LACP status as 'up'..."
POD_NAME=$(oc get pods -n openshift-pf-status-relay-operator -l app=pf-status-relay-ds -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    log_info "Checking logs for pod: $POD_NAME"
    oc logs "$POD_NAME" -n openshift-pf-status-relay-operator | grep -i "lacp is up" || log_warn "LACP 'up' message not found yet"
else
    log_error "PFLACPMonitor pod not found"
fi

# Step 11: Create test namespace
log_info "Step 11: Creating test namespace..."
oc apply -f namespace.yaml

# Step 12: Create SR-IOV Networks (NADs) for bonded PFs on worker-0
log_info "Step 12: Creating SR-IOV Networks for bonded PF interfaces..."
oc apply -f sriovnetwork-net1.yaml
oc apply -f sriovnet-net2.yaml

# Step 13: Create Network Attachment Definition for bonded interface
log_info "Step 13: Creating NAD for bonded interface..."
oc apply -f nad-bond.yaml

# Step 14: Create client bond pod on worker-0
log_info "Step 14: Deploying client bond pod on worker-0..."
oc apply -f client-bond.yaml

log_info "Waiting for client bond pod to start..."
sleep 5

# Step 15: Create SR-IOV Network for test client pod on worker-1
log_info "Step 15: Creating SR-IOV Network for client pod on worker-1..."
oc apply -f sriovnetwork-client.yaml

# Step 16: Create client pod on worker-1
log_info "Step 16: Deploying client pod on worker-1..."
oc apply -f client-pod.yaml

log_info "Waiting for client pod to start..."
sleep 5

# Final verification
log_info "Final verification - checking all pods..."
oc get pods -n openshift-sriov-network-operator
oc get pods -n openshift-pf-status-relay-operator
oc get pods -n $(oc get namespaces -o jsonpath='{.items[?(@.metadata.annotations.test=="true")].metadata.name}' 2>/dev/null || echo "default")

log_info "Setup complete!"
log_warn "Manual verification checklist:"
echo "  1. LACP bond status shows port state 63 on both bonds"
echo "  2. Switch shows LACP state with Dist/Col/Syn/Aggr all 'Yes'"
echo "  3. PFLACPMonitor logs show 'lacp is up' for ens5f0 and ens5f1"
echo "  4. Client pods are running on both worker-0 and worker-1"
echo "  5. VF interfaces are available in client pods"
