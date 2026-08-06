#!/bin/bash
# Deploy HyperFlow onto the alice-k8s-datalake k3s cluster for the 1000genome
# capacity experiments.
#
#   ./cluster/deploy.sh            # install
#   ./cluster/deploy.sh --uninstall
#
# Run from the root of the hyperflow-k8s-deployment checkout.

set -euo pipefail

KUBECONFIG_FILE="${KUBECONFIG_FILE:-/home/balis/1000genome-workflow/bbalis.kubeconfig}"
NS="${NS:-hyperflow}"
K="kubectl --kubeconfig=$KUBECONFIG_FILE"
H="helm --kubeconfig=$KUBECONFIG_FILE"

# server-0 holds the shared filesystem, redis and the engine, and is never a
# worker -- the NFS backing store is pinned to it by node affinity, so it must
# not be relabelled between sweep points. That reservation leaves avx2-0 (8),
# workers-0 (16) and workers-1 (16) free to form the capacity ladder: 8, 16, 24,
# 32, 40 slots via ./cluster/set-capacity.sh.
#
# The db-* nodes are tainted dedicated=database and the nfs-role node is tainted
# node-role/nfs; the HyperFlow charts support no tolerations, so all four stay
# out and 24 of the cluster's 70 vCPUs are unreachable.
MASTER_NODE="${MASTER_NODE:-alice-k8s-datalake-server-0}"
WORKER_NODES="${WORKER_NODES:-alice-k8s-datalake-workers-0 alice-k8s-datalake-workers-1}"

if [ "${1:-}" = "--uninstall" ]; then
    $H uninstall -n "$NS" hf-run  2>/dev/null || true
    $K delete namespace "$NS" --wait=false 2>/dev/null || true
    $K delete priorityclass hyperflow-worker 2>/dev/null || true
    for n in $MASTER_NODE $WORKER_NODES; do
        $K label node "$n" hyperflow-wms/nodepool- 2>/dev/null || true
    done
    echo "Uninstalled. Host-provisioned volumes are released with the namespace."
    exit 0
fi

echo "==> Labelling nodes"
$K label node "$MASTER_NODE" hyperflow-wms/nodepool=hfmaster --overwrite
for n in $WORKER_NODES; do
    $K label node "$n" hyperflow-wms/nodepool=hfworker --overwrite
done

echo "==> Namespace, shared RWX volume, PriorityClass"
$K apply -f cluster/00-prereqs.yaml

echo "==> Waiting for the shared volume to bind"
$K wait -n "$NS" --for=jsonpath='{.status.phase}'=Bound pvc/nfs --timeout=3m

echo "==> hf-run (redis + engine; the volume already exists)"
$H upgrade --install hf-run charts/hyperflow-run \
    -n "$NS" \
    -f cluster/values-run-1000genome.yaml \
    --wait --timeout 10m

echo "==> State"
$K get pv,pvc -n "$NS"
$K get pods -n "$NS" -o wide

cat <<'EOF'

The engine is parked in an idle loop (HF_VAR_DEBUG=1). Stage a workflow and run
it with:

    ./cluster/stage-workflow.sh <path-to-harness-workflow-dir>
    ./cluster/run-workflow.sh

EOF
