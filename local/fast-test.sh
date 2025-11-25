#!/bin/bash

# Fast local testing script for Hyperflow
# This script sets up a Kind cluster and runs a workflow using locally-built images
#
# Usage:
#   ./local/fast-test.sh                        # Use existing cluster/ops if available (default)
#   ./local/fast-test.sh --clean                # Force clean reinstall from scratch
#   ./local/fast-test.sh --admission-controller # Enable K8s admission controller with debug
#
# To build HyperFlow engine image before running this script:
#   cd /path/to/hyperflow && make image
#
# For iterative development, use rebuild-and-test.sh instead.

set -e

# Parse command line arguments
FORCE_CLEAN=false
DRY_RUN=false
ADMISSION_CONTROLLER=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean|--from-scratch)
            FORCE_CLEAN=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --admission-controller)
            ADMISSION_CONTROLLER=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean, --from-scratch    Delete and recreate cluster and hf-ops"
            echo "  --dry-run                  Enable dry run mode (jobs return immediately with success)"
            echo "  --admission-controller     Enable K8s admission controller with 3-node cluster settings"
            echo "  --help, -h                 Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  CLUSTER_NAME               Kind cluster name (default: hyperflow-test)"
            echo "  HF_ENGINE_IMAGE            HyperFlow engine image (default: hyperflowwms/hyperflow:latest)"
            echo "  WORKER_IMAGE               Worker image (default: hyperflowwms/montage2-worker:latest)"
            echo "  DATA_IMAGE                 Workflow data image (default: montage2-2mass-025-latest)"
            echo "  AUTO_RUN                   Auto-start workflow (default: true)"
            echo "  DRY_RUN                    Enable dry run mode (default: false)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-hyperflow-test}"
WORKFLOW="${WORKFLOW:-montage2}"
HF_ENGINE_IMAGE="${HF_ENGINE_IMAGE:-hyperflowwms/hyperflow:latest}"
WORKER_IMAGE="${WORKER_IMAGE:-hyperflowwms/montage2-worker:latest}"
DATA_IMAGE="${DATA_IMAGE:-hyperflowwms/montage2-workflow-data:montage2-2mass-025-latest}"
AUTO_RUN="${AUTO_RUN:-true}"
DRY_RUN="${DRY_RUN:-false}"

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
if [ "$FORCE_CLEAN" = "true" ]; then
    # Force clean mode - delete existing cluster
    log_info "Clean mode: Deleting existing cluster and infrastructure..."
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    log_info "Creating fresh Kind cluster '$CLUSTER_NAME'..."
    kind create cluster --name "$CLUSTER_NAME" --config local/kind-config-3n.yaml
elif kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    # Cluster exists - reuse it
    log_info "Using existing Kind cluster '$CLUSTER_NAME'"
    kubectl config use-context "kind-${CLUSTER_NAME}"
else
    # Cluster doesn't exist - create it
    log_info "Creating Kind cluster '$CLUSTER_NAME'..."
    kind create cluster --name "$CLUSTER_NAME" --config local/kind-config-3n.yaml
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
if helm list | grep -q "^hf-ops"; then
    # hf-ops already installed - reuse it
    log_info "Using existing hf-ops installation"
else
    # hf-ops not installed - install it
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
fi

# Step 4: Delete old workflow run and install new one
if helm list | grep -q "^hf-run"; then
    log_info "Deleting previous workflow run..."
    helm delete hf-run
    log_info "Waiting for previous workflow pods to terminate..."
    kubectl wait --for=delete pod -l component=hyperflow-engine --timeout=60s 2>/dev/null || true
    sleep 2
fi

log_info "Installing hyperflow-run chart for workflow '$WORKFLOW'..."
if [ "$DRY_RUN" = "true" ]; then
    log_warn "DRY RUN MODE is not yet fully implemented (requires executor fix)"
    log_warn "Jobs will run normally. To enable dry run, update hyperflow-job-executor to check HF_VAR_DRY_RUN === '1'"
fi

# Build admission controller config if enabled
ADMISSION_VALUES_FILE=""
if [ "$ADMISSION_CONTROLLER" = "true" ]; then
    log_info "Enabling K8s admission controller with 3-node cluster settings..."

    # Create temporary values file with admission controller settings
    ADMISSION_VALUES_FILE=$(mktemp)
    cat > "$ADMISSION_VALUES_FILE" <<EOF
hyperflow-engine:
  containers:
    worker:
      additionalVariables:
        - name: HF_VAR_DEBUG
          value: "0"
        - name: HF_VAR_CPU_REQUEST
          value: "0.2"
        - name: HF_VAR_MEM_REQUEST
          value: "128Mi"
        - name: NODE_OPTIONS
          value: "--max-old-space-size=512"
        - name: HF_VAR_ADMISSION_CONTROLLER
          value: "1"
        - name: HF_VAR_ADMISSION_PENDING_MAX
          value: "120"
        - name: HF_VAR_ADMISSION_FILL_RATE
          value: "15"
        - name: HF_VAR_ADMISSION_BURST
          value: "80"
        - name: HF_VAR_ADMISSION_ADAPTIVE
          value: "1"
        - name: HF_VAR_ADMISSION_DEBUG
          value: "1"
EOF

    ADMISSION_FLAGS="-f $ADMISSION_VALUES_FILE"
else
    ADMISSION_FLAGS=""
fi

helm upgrade --install hf-run charts/hyperflow-run \
    --dependency-update \
    -f local/values-fast-test-run.yaml \
    --set hyperflow-engine.containers.hyperflow.image="$HF_ENGINE_IMAGE" \
    --set hyperflow-engine.containers.worker.image="$WORKER_IMAGE" \
    --set hyperflow-nfs-data.workflow.image="$DATA_IMAGE" \
    --set hyperflow-engine.containers.hyperflow.autoRun="$AUTO_RUN" \
    $ADMISSION_FLAGS \
    --wait \
    --timeout 10m

# Clean up temporary admission controller values file
if [ -n "$ADMISSION_VALUES_FILE" ] && [ -f "$ADMISSION_VALUES_FILE" ]; then
    rm -f "$ADMISSION_VALUES_FILE"
fi

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
