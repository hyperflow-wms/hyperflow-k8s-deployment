#!/bin/bash
# Copy a prepared harness workflow directory onto the shared volume.
#
#   ./cluster/stage-workflow.sh ~/1000genome-workflow/engines/hyperflow/harness/workflow-q3-multi-region
#
# Only execute-time inputs are copied. Everything a run produces
# (chr*n*.tar.gz, output_no_sift/, plots_no_sift/, logs-hf/) is left behind,
# along with the pipeline artefacts (plan.json, intent.json, data.csv), which
# matter only to the PLAN/EXTRACT/GENERATE phases running on the laptop.
# For Q3 this is about 46 MB, of which ALL.chr7.cftr.vcf is 92%.

set -euo pipefail

SRC="${1:?usage: stage-workflow.sh <workflow-dir>}"
KUBECONFIG_FILE="${KUBECONFIG_FILE:-/home/balis/1000genome-workflow/bbalis.kubeconfig}"
NS="${NS:-hyperflow}"
K="kubectl --kubeconfig=$KUBECONFIG_FILE -n $NS"

POD=$($K get pods -l component=hyperflow-engine -o jsonpath='{.items[0].metadata.name}')
[ -n "$POD" ] || { echo "No engine pod found in namespace $NS" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp "$SRC/workflow.json" "$STAGE/"
cp "$SRC/columns.txt"   "$STAGE/"

# Region VCFs and their annotation files. The .tbi indices and the
# *.sites.annotation.* files are EXTRACT-phase artefacts that no process in the
# DAG opens, so they are skipped.
find "$SRC" -maxdepth 1 -name 'ALL.*.vcf' ! -name '*.sites.*' -exec cp {} "$STAGE/" \;

# Population files: bare three-letter names, no extension (AFR, EUR, ...).
find "$SRC" -maxdepth 1 -type f -regextype posix-extended -regex '.*/[A-Z]{3}' \
    -exec cp {} "$STAGE/" \;

echo "==> Staging $(du -sh "$STAGE" | cut -f1) from $(basename "$SRC")"
ls -la "$STAGE"

# Clear any previous run so a re-run starts from the same state the harness's
# --execute-only produces.
$K exec "$POD" -c hyperflow -- sh -c '
    cd /work_dir &&
    rm -rf chr*n-*/ chr*n/ logs-hf plots_no_sift output_no_sift &&
    rm -f chr*n*.tar.gz chr*-*.tar.gz sifted.SIFT.*.txt wftrace-*.log postprocStart
' 2>/dev/null || true

$K cp "$STAGE/." "$POD:/work_dir" -c hyperflow

echo "==> Staged. Contents of /work_dir:"
$K exec "$POD" -c hyperflow -- ls -la /work_dir
