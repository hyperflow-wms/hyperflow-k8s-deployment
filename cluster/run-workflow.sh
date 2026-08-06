#!/bin/bash
# Execute the staged workflow and collect the measurement artefacts.
#
#   ./cluster/run-workflow.sh <results-dir>
#
# The engine is deployed parked (HF_VAR_DEBUG=1), so this is the Kubernetes
# equivalent of the harness's --execute-only: the same deployment serves every
# point of a sweep, and nothing is re-planned or re-extracted between runs.
#
# Timing is taken from the engine's own log rather than from this script's wall
# clock. The engine's per-task "time=Ns" figures come from monotonic
# performance.now() deltas inside the cluster, so a WSL2 host suspend on the
# laptop corrupts neither them nor the run -- only this script's own view of
# elapsed time, which is why that view is not what gets recorded.

set -euo pipefail

OUT="${1:?usage: run-workflow.sh <results-dir>}"
KUBECONFIG_FILE="${KUBECONFIG_FILE:-/home/balis/1000genome-workflow/bbalis.kubeconfig}"
NS="${NS:-hyperflow}"
K="kubectl --kubeconfig=$KUBECONFIG_FILE -n $NS"

mkdir -p "$OUT"
POD=$($K get pods -l component=hyperflow-engine -o jsonpath='{.items[0].metadata.name}')

# Record what capacity was actually in force, so a result can never be read
# without knowing the setting that produced it.
{
    echo "date_utc:  $(date -u +%FT%TZ)"
    echo "pod:       $POD"
    echo "worker:    $($K get deploy hyperflow-engine -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="HF_VAR_WORKER_CONTAINER")].value}')"
    echo "cpuRequest:$($K get deploy hyperflow-engine -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="HF_VAR_CPU_REQUEST")].value}')"
    echo "quota:"
    $K get resourcequota hflow-requests -o jsonpath='{.spec.hard}' 2>/dev/null || echo "  (none)"
    echo
    echo "worker nodes:"
    kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes -l hyperflow-wms/nodepool=hfworker \
        -o custom-columns='NAME:.metadata.name,CPU:.status.allocatable.cpu' --no-headers
} > "$OUT/run-config.txt"

echo "==> Running workflow (engine log -> $OUT/engine.log)"
$K exec "$POD" -c hyperflow -- sh -c 'cd /work_dir && hflow run workflow.json' \
    2>&1 | tee "$OUT/engine.log"

echo "==> Collecting per-task logs"
# These are written by the job executor inside each worker onto the shared
# volume, exactly as in the Docker harness, so the calibration reads the same
# format from both backends. Copy them off now: the next run wipes logs-hf.
$K cp "$POD:/work_dir/logs-hf" "$OUT/logs-hf" -c hyperflow

echo "==> Summary"
{
    echo "tasks logged: $(find "$OUT/logs-hf" -name 'task-*[!_stdout][!_stderr].log' 2>/dev/null | wc -l)"
    grep -oE 'task finished: [a-z_]+ .* time=[0-9.]+s' "$OUT/engine.log" 2>/dev/null |
        sed -E 's/task finished: ([a-z_]+).*time=([0-9.]+)s/\1 \2/' |
        awk '{n[$1]++; s[$1]+=$2; if($2>m[$1]) m[$1]=$2}
             END {printf "%-20s %5s %10s %10s\n","stage","n","mean_s","max_s";
                  for (k in n) printf "%-20s %5d %10.1f %10.1f\n", k, n[k], s[k]/n[k], m[k]}' |
        sort
} | tee "$OUT/summary.txt"

echo
echo "Artefacts in $OUT: engine.log, logs-hf/, run-config.txt, summary.txt"
