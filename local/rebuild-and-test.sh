#!/bin/bash

# Convenience script to rebuild Hyperflow engine and test it locally
# This script assumes you have the hyperflow source code in a sibling directory
#
# Usage:
#   ./local/rebuild-and-test.sh                    # Standard rebuild and test
#   ./local/rebuild-and-test.sh --admission-controller  # Test with admission controller enabled

set -e

# Parse command line arguments
EXTRA_ARGS=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --admission-controller)
            EXTRA_ARGS="$EXTRA_ARGS --admission-controller"
            shift
            ;;
        --clean|--from-scratch)
            EXTRA_ARGS="$EXTRA_ARGS --clean"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--admission-controller] [--clean]"
            exit 1
            ;;
    esac
done

# Configuration
HYPERFLOW_DIR="${HYPERFLOW_DIR:-../hyperflow}"
HF_ENGINE_IMAGE="${HF_ENGINE_IMAGE:-hyperflowwms/hyperflow:latest}"
CLUSTER_NAME="${CLUSTER_NAME:-hyperflow-test}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Check if hyperflow directory exists
if [ ! -d "$HYPERFLOW_DIR" ]; then
    log_info "HyperFlow directory not found at: $HYPERFLOW_DIR"
    log_info "Please set HYPERFLOW_DIR environment variable or clone hyperflow to ../hyperflow"
    exit 1
fi

# Step 1: Build Hyperflow engine image using make
log_info "Building HyperFlow engine image from: $HYPERFLOW_DIR"
cd "$HYPERFLOW_DIR"
log_info "Running 'make image' (recommended build method)..."
make image

# Tag the image if a custom tag was specified
if [ "$HF_ENGINE_IMAGE" != "hyperflowwms/hyperflow:latest" ]; then
    log_info "Tagging image as: $HF_ENGINE_IMAGE"
    docker tag hyperflowwms/hyperflow:latest "$HF_ENGINE_IMAGE"
fi

# Step 2: Return to deployment directory
cd - > /dev/null

# Step 3: Delete old hyperflow-run release if it exists
log_info "Cleaning up old hyperflow-run release..."
helm delete hf-run 2>/dev/null || log_info "No existing hf-run release to delete"

# Wait for pods to terminate
log_info "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l component=hyperflow-engine --timeout=60s 2>/dev/null || true

# Step 4: Load image into Kind cluster
log_info "Loading image into Kind cluster..."
kind load docker-image "$HF_ENGINE_IMAGE" --name "$CLUSTER_NAME"

# Step 5: Run fast test with newly built image
log_info "Running fast test with newly built image..."
# Note: fast-test.sh will automatically reuse existing cluster and hf-ops
HF_ENGINE_IMAGE="$HF_ENGINE_IMAGE" ./local/fast-test.sh $EXTRA_ARGS

log_info "Done!"
