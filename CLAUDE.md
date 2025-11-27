## Running a sample workflow using HyperFlow

For subsequent kubernetes related actions i prefer to execute a helm or kubectl commands rather than using MCP server.

1. Create workerpools namespace

The namespace name must be unique in the kubernetes cluster. The subsequent commands must be executed within the same namespace.

```bash
kubectl create namespace hyperflow
```

2. Install HyperFlow helm charts

```bash
helm upgrade -n hyperflow --dependency-update -i hf-ops ./charts/hyperflow-ops --set worker-pools.enabled=true
helm upgrade -n hyperflow --dependency-update -i hf-run-montage ./charts/hyperflow-run
```

### Create ResourceQuota

The implementation of the Worker Pools Operator requires `ResourceQuota` to be present in the namespace.

```bash
kubectl create -n hyperflow quota hflow-requests --hard=requests.cpu=21,requests.memory=60Gi
```

### Wait until all pods in workflow namespace are in running state

```bash
kubectl wait -n hyperflow --for=condition=available --timeout=1200s deployment --all
```

### Begin sample workflow calculation


```bash
kubectl exec -n hyperflow -it deployment/hyperflow-engine -- sh -c 'hflow run /work_dir'
```

### Cleanup

```bash
helm uninstall -n hyperflow hf-run-montage
helm uninstall -n hyperflow hf-ops
kubectl delete namespace hyperflow --force --grace-period=0
```