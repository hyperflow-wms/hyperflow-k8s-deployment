# HyperFlow Local Fast Testing

Fast local testing of HyperFlow workflows using Kind (Kubernetes in Docker) with locally-built images.

## 🎯 Why This Exists

**Traditional workflow:** Build image → Push to Docker Hub (2-5 min) → Kind pulls → Deploy → Manual run
**Fast workflow:** Build image → Load to Kind (seconds) → Deploy → Auto-run

## 🚀 Quick Start

### First Time Setup

```bash
# Create cluster, install infrastructure, run workflow
./local/fast-test.sh
```

This creates a Kind cluster with 3 worker nodes, installs all necessary components (RabbitMQ, KEDA, NFS, etc.), and runs a small Montage2 workflow automatically.

To run a different workflow, override settings using envs, e.g.:
```bash
WORKFLOW=montage-tiny \
  WORKER_IMAGE=hyperflowwms/montage-worker:latest \
  DATA_IMAGE=matplinta/montage-workflow-data:degree0.25 \
  ./local/fast-test.sh
```

**Smart defaults:** The script automatically reuses existing cluster and infrastructure on subsequent runs for maximum speed. Use `./local/fast-test.sh --clean` to force a fresh reinstall.

### Iterative Development (Most Common)

When you modify HyperFlow engine code:

```bash
# Build, load, and test in one command
export HYPERFLOW_DIR=../hyperflow  # Path to your HyperFlow source
./local/rebuild-and-test.sh
```

This script:
1. Builds HyperFlow engine using `make image`
2. Loads image directly into Kind (no Docker Hub!)
3. Deletes old workflow deployment
4. Deploys new version with updated image
5. Auto-starts workflow and shows logs

**Cluster and infrastructure stay running** - only the workflow is reinstalled. This is the fastest iteration mode (~30-60 seconds).

## 📁 Files

- **`fast-test.sh`** - Full setup: creates cluster, installs everything
- **`rebuild-and-test.sh`** - Quick iteration: rebuilds engine, reinstalls workflow only
- **`kind-config-3n.yaml`** - Cluster configuration (3 worker nodes with proper labels)
- **`values-fast-test-ops.yaml`** - Optimized infrastructure settings
- **`values-fast-test-run.yaml`** - Optimized workflow settings

## ⚙️ Configuration

Control behavior with environment variables:

### rebuild-and-test.sh
```bash
HYPERFLOW_DIR=../hyperflow           # Path to HyperFlow source
HF_ENGINE_IMAGE=hyperflowwms/hyperflow:latest  # Image name/tag
CLUSTER_NAME=hyperflow-test          # Kind cluster name
```

### fast-test.sh
```bash
# Command line options
./local/fast-test.sh           # Use existing cluster/ops (default)
./local/fast-test.sh --clean   # Force fresh reinstall from scratch

# Environment variables
CLUSTER_NAME=hyperflow-test          # Kind cluster name
HF_ENGINE_IMAGE=...                  # HyperFlow engine image
WORKER_IMAGE=...                     # Worker image
DATA_IMAGE=...                       # Workflow data image
AUTO_RUN=true/false                  # Auto-start workflow (default: true)
```

## 💡 Common Scenarios

### Daily Development Workflow
```bash
# Morning: set up once
./local/fast-test.sh

# All day: quick iterations (keeps cluster & infrastructure)
./local/rebuild-and-test.sh
# ... make changes ...
./local/rebuild-and-test.sh
# ... make more changes ...
./local/rebuild-and-test.sh
```

### Test Different Workflow Sizes
```bash
# Tiny workflow (fastest, good for quick tests - ~60 jobs)
WORKER_IMAGE=hyperflowwms/montage-worker:je-1.3.2 \
DATA_IMAGE=matplinta/montage-workflow-data:degree0.25 \
./local/fast-test.sh

# Small workflow (default - ~600 jobs)
./local/fast-test.sh

# Large workflow (~16k jobs)
DATA_IMAGE=hyperflowwms/montage2-workflow-data:montage2-2mass-3.0-latest \
./local/fast-test.sh
```

### Test Custom Worker Image
```bash
# Build your worker
cd /path/to/worker && docker build -t my-worker:test .

# Load into Kind
kind load docker-image my-worker:test --name hyperflow-test

# Test it (automatically reuses existing cluster/ops)
cd /path/to/hyperflow-k8s-deployment
WORKER_IMAGE=my-worker:test ./local/fast-test.sh
```

### Force Clean Reinstall
```bash
# Delete and recreate everything from scratch
./local/fast-test.sh --clean
```

### Manual Testing (No Auto-Run)
```bash
# Start without running workflow
AUTO_RUN=false ./local/fast-test.sh

# Then manually exec into pod
HF_POD=$(kubectl get pods -l component=hyperflow-engine -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $HF_POD -- sh
cd /work_dir && hflow run .
```

## 🔍 Monitoring

### View Logs
```bash
# Follow HyperFlow engine logs
kubectl logs -f -l component=hyperflow-engine -c hyperflow

# Get pod name
HF_POD=$(kubectl get pods -l component=hyperflow-engine -o jsonpath='{.items[0].metadata.name}')

# View specific container
kubectl logs -f $HF_POD -c hyperflow
kubectl logs -f $HF_POD -c worker
```

### Check Status
```bash
# All pods
kubectl get pods -w

# Jobs
kubectl get jobs -w

# Workflow files
kubectl exec $HF_POD -- ls -la /work_dir

# Copy workflow results (example for Montage - outputs .jpg files)
kubectl exec $HF_POD -- find /work_dir -name "*.jpg"

# Copy all output files (e.g., all .jpg files from Montage)
kubectl exec $HF_POD -- sh -c 'cd /work_dir && tar czf - *.jpg' | tar xzf -
```

## 🧹 Cleanup

```bash
# Delete workflow only (keeps infrastructure for next test)
helm delete hf-run

# Delete everything except cluster
helm delete hf-run && helm delete hf-ops

# Full cleanup including cluster
helm delete hf-run
helm delete hf-ops
kind delete cluster --name hyperflow-test
```

## ❓ Troubleshooting

### Image Not Found
```bash
# Check if image exists
docker images | grep hyperflow

# Load it into Kind
kind load docker-image hyperflowwms/hyperflow:latest --name hyperflow-test

# Verify it's loaded
docker exec -it hyperflow-test-control-plane crictl images | grep hyperflow
```

### Pods Stuck in Pending
```bash
# Check node labels (required: hfmaster and hfworker)
kubectl get nodes --show-labels | grep hyperflow-wms

# If labels missing, recreate cluster
kind delete cluster --name hyperflow-test
./local/fast-test.sh
```

### Workflow Doesn't Start
```bash
# Check logs
kubectl logs -l component=hyperflow-engine -c hyperflow --tail=50

# Check if workflow.json exists
kubectl exec $(kubectl get pods -l component=hyperflow-engine -o jsonpath='{.items[0].metadata.name}') -- ls -la /work_dir/
```

### RabbitMQ Image Pull Errors
If you see `ErrImagePull` for RabbitMQ, it's due to Bitnami's catalog changes. The images are now in the `bitnamilegacy` repository, which is already configured in `values-fast-test-ops.yaml`.

Just wait - Kubernetes will retry and eventually succeed (usually 2-5 minutes).

### Check Events
```bash
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

## 🔑 Key Technical Details

### How It Works

1. **Direct Image Loading**: `kind load docker-image` exports the image as tar and loads it into Kind's containerd, making it available to all nodes instantly (5-10 sec vs 2-5 min via registry).

2. **Image Pull Policy**: `imagePullPolicy: IfNotPresent` makes Kubernetes check locally first before pulling from registry.

3. **Auto-Start**: The HyperFlow engine container is configured to automatically run `hflow run workflow.json` on startup.

4. **Optimized Resources**: Reduced CPU/memory requests and disabled heavy monitoring for faster local testing.

### Node Labels

The Kind cluster uses node labels for pod placement:
- `hyperflow-wms/nodepool: hfmaster` - for HyperFlow engine, Redis, RabbitMQ, NFS (1 node)
- `hyperflow-wms/nodepool: hfworker` - for workflow job pods (2 nodes)

## 🛠️ Requirements

- [Docker](https://docs.docker.com/get-docker/)
- [Kind](https://kind.sigs.k8s.io/) v0.20+
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/) v3.0+
- [make](https://www.gnu.org/software/make/) (for building HyperFlow)

## 💡 Tips

**Use aliases** for common commands:
   ```bash
   alias hf-test='cd /path/to/hyperflow-k8s-deployment && ./local/rebuild-and-test.sh'
   alias hf-logs='kubectl logs -f -l component=hyperflow-engine -c hyperflow'
   alias hf-clean='helm delete hf-run'
   ```

## 📝 Notes

- **HyperFlow Build**: Always use `make image` in the HyperFlow directory (recommended method)
- **Bitnami Images**: Uses `bitnamilegacy` repository due to Bitnami catalog changes
- **Resource Limits**: Fast test configs use reduced resources - adjust in `values-fast-test-*.yaml` if needed
- **Monitoring**: Prometheus/Grafana disabled by default for faster startup - enable in `values-fast-test-ops.yaml` if needed

---

