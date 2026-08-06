#!/bin/bash
# Set the capacity available to worker pods, for a capacity sweep.
#
#   ./cluster/set-capacity.sh 8|16|24|32|40
#
# Capacity is varied by labelling nodes, not by a ResourceQuota. With
# HF_VAR_CPU_REQUEST=1 each task holds a whole core, so the labelled cores are
# the slot count, and surplus tasks queue in the scheduler as Pending pods --
# which the scheduler clears on pod-completion events with no backoff. A quota
# instead rejects the pod at admission and leaves the Job controller retrying on
# an exponential backoff, which would land in the measured makespan.
# See docs/CLUSTER-CAPACITY-NOTES.md sections 3 and 4 in the 1000genome repo.
#
# server-0 stays hfmaster throughout and is never a worker: it holds the NFS
# server, redis and the engine, and the shared filesystem must not move when
# capacity changes.

set -euo pipefail

WANT="${1:?usage: set-capacity.sh <8|16|24|32|40>}"
KUBECONFIG_FILE="${KUBECONFIG_FILE:-/home/balis/1000genome-workflow/bbalis.kubeconfig}"
K="kubectl --kubeconfig=$KUBECONFIG_FILE"

AVX2=alice-k8s-datalake-avx2-0     # 8 cores
W0=alice-k8s-datalake-workers-0    # 16 cores
W1=alice-k8s-datalake-workers-1    # 16 cores
POOL="$AVX2 $W0 $W1"

case "$WANT" in
    8)  WORKERS="$AVX2" ;;
    16) WORKERS="$W0" ;;
    24) WORKERS="$W0 $AVX2" ;;
    32) WORKERS="$W0 $W1" ;;
    40) WORKERS="$W0 $W1 $AVX2" ;;
    *)  echo "Capacity must be one of 8, 16, 24, 32, 40 (node-sized steps)" >&2; exit 1 ;;
esac

for n in $POOL; do
    if [[ " $WORKERS " == *" $n "* ]]; then
        $K label node "$n" hyperflow-wms/nodepool=hfworker --overwrite >/dev/null
    else
        # Unlabelled rather than hfmaster: a second hfmaster would let redis or
        # the engine be rescheduled away from the node holding the NFS backing
        # store, whose PV is pinned there by node affinity.
        $K label node "$n" hyperflow-wms/nodepool- >/dev/null 2>&1 || true
    fi
done

echo "==> Capacity now $WANT slots (one core per task):"
$K get nodes -l hyperflow-wms/nodepool=hfworker \
    -o custom-columns='NAME:.metadata.name,CPU:.status.allocatable.cpu' --no-headers
