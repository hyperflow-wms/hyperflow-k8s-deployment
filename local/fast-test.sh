#!/bin/bash

# Fast local testing script for Hyperflow
# This script sets up a Kind cluster and runs a workflow using locally-built images
#
# To build HyperFlow engine image before running this script:
#   cd /path/to/hyperflow && make image
#
# For iterative development, use rebuild-and-test.sh instead.

set -e

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-hyperflow-test}"
WORKFLOW="${WORKFLOW:-montage2}"
HF_ENGINE_IMAGE="${HF_ENGINE_IMAGE:-hyperflowwms/hyperflow:latest}"
WORKER_IMAGE="${WORKER_IMAGE:-hyperflowwms/montage2-worker:latest}"
DATA_IMAGE="${DATA_IMAGE:-hyperflowwms/montage2-workflow-data:montage2-2mass-025-latest}"
SKIP_CLUSTER_CREATE="${SKIP_CLUSTER_CREATE:-false}"
SKIP_OPS_INSTALL="${SKIP_OPS_INSTALL:-false}"
AUTO_RUN="${AUTO_RUN:-true}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Step 1: Create or reuse Kind cluster
if [ "$SKIP_CLUSTER_CREATE" = "false" ]; then
    log_info "Creating Kind cluster '$CLUSTER_NAME'..."
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster '$CLUSTER_NAME' already exists. Deleting it..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    kind create cluster --name "$CLUSTER_NAME" --config local/kind-config-3n.yaml
else
    log_info "Skipping cluster creation (SKIP_CLUSTER_CREATE=true)"
fi

# Step 2: Load locally-built images into Kind
log_info "Loading locally-built images into Kind cluster..."

# Check if images exist locally and load them
if docker image inspect "$HF_ENGINE_IMAGE" >/dev/null 2>&1; then
    log_info "Loading HyperFlow engine image: $HF_ENGINE_IMAGE"
    kind load docker-image "$HF_ENGINE_IMAGE" --name "$CLUSTER_NAME"
else
    log_warn "HyperFlow engine image '$HF_ENGINE_IMAGE' not found locally. Will pull from registry."
fi

if docker image inspect "$WORKER_IMAGE" >/dev/null 2>&1; then
    log_info "Loading worker image: $WORKER_IMAGE"
    kind load docker-image "$WORKER_IMAGE" --name "$CLUSTER_NAME"
else
    log_warn "Worker image '$WORKER_IMAGE' not found locally. Will pull from registry."
fi

if docker image inspect "$DATA_IMAGE" >/dev/null 2>&1; then
    log_info "Loading data image: $DATA_IMAGE"
    kind load docker-image "$DATA_IMAGE" --name "$CLUSTER_NAME"
else
    log_warn "Data image '$DATA_IMAGE' not found locally. Will pull from registry."
fi

# Step 3: Install hyperflow-ops if needed
if [ "$SKIP_OPS_INSTALL" = "false" ]; then
    log_info "Installing hyperflow-ops chart..."
    log_info "This may take a few minutes (installing RabbitMQ, KEDA, NFS provisioner, etc.)..."
    helm upgrade --install hf-ops charts/hyperflow-ops \
        --dependency-update \
        --wait \
        --timeout 15m \
        -f local/values-fast-test-ops.yaml

    log_info "Waiting for all ops components to be ready..."
    log_info "Checking pod status..."

    # Check for image pull errors
    sleep 10
    if kubectl get pods -A | grep -q "ErrImagePull\|ImagePullBackOff"; then
        log_warn "Some pods are failing to pull images. This is common with Kind."
        log_warn "Checking which images are failing..."
        kubectl get pods -A | grep -E "ErrImagePull|ImagePullBackOff" || true
        log_warn "You may need to wait for retry or check 'kubectl describe pod <pod-name>'"
    fi

    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=rabbitmq --timeout=10m 2>/dev/null || log_warn "RabbitMQ pod may still be starting (check: kubectl get pods -A)"
    kubectl wait --for=condition=ready pod -l app=nfs-server-provisioner --timeout=5m 2>/dev/null || log_warn "NFS provisioner pod may still be starting"
else
    log_info "Skipping hyperflow-ops installation (SKIP_OPS_INSTALL=true)"
fi

# Step 4: Install hyperflow-run chart
log_info "Installing hyperflow-run chart for workflow '$WORKFLOW'..."
helm upgrade --install hf-run charts/hyperflow-run \
    --dependency-update \
    --set hf-engine-image="$HF_ENGINE_IMAGE" \
    --set wf-worker-image="$WORKER_IMAGE" \
    --set wf-input-data-image="$DATA_IMAGE" \
    --set hyperflow-engine.containers.hyperflow.autoRun="$AUTO_RUN" \
    --wait \
    --timeout 10m \
    -f local/values-fast-test-run.yaml

# Step 5: Monitor workflow execution
if [ "$AUTO_RUN" = "true" ]; then
    log_info "Workflow started automatically. Monitoring execution..."

    # Wait for HyperFlow engine pod to be created
    log_info "Waiting for HyperFlow engine pod to be created..."
    for i in {1..30}; do
        HF_POD=$(kubectl get pods -l component=hyperflow-engine -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$HF_POD" ]; then
            log_info "HyperFlow engine pod found: $HF_POD"
            break
        fi
        if [ $i -eq 30 ]; then
            log_error "Timeout waiting for HyperFlow engine pod to be created"
            log_info "Check pod status with: kubectl get pods"
            exit 1
        fi
        sleep 2
    done

    # Wait for pod to be running
    log_info "Waiting for pod to be running..."
    kubectl wait --for=condition=ready pod -l component=hyperflow-engine --timeout=5m || log_warn "Pod may still be starting"

    log_info "You can follow logs with: kubectl logs -f $HF_POD -c hyperflow"
    echo ""
    log_info "Tailing logs (Ctrl+C to stop)..."
    kubectl logs -f "$HF_POD" -c hyperflow || true
else
    log_info "Workflow NOT auto-started. To run manually:"

    # Wait for HyperFlow engine pod to be created
    for i in {1..30}; do
        HF_POD=$(kubectl get pods -l component=hyperflow-engine -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$HF_POD" ]; then
            break
        fi
        sleep 2
    done

    if [ -n "$HF_POD" ]; then
        echo "  kubectl exec -it $HF_POD -- sh"
        echo "  cd /work_dir && hflow run ."
    else
        echo "  kubectl get pods  # Find the hyperflow-engine pod first"
    fi
fi

log_info "Done! To cleanup: helm delete hf-run && helm delete hf-ops"
