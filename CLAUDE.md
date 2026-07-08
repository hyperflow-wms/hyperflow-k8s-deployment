## Running a sample workflow using HyperFlow

For subsequent kubernetes related actions i prefer to execute a helm or kubectl commands rather than using MCP server.

1. Create workerpools namespace

The namespace name must be unique in the kubernetes cluster. The subsequent commands must be executed within the same namespace.

```bash
kubectl create namespace hyperflow
```

2. Install `hyperflow-ops` helm chart

```bash
helm install -n hyperflow --dependency-update hf-ops ./charts/hyperflow-ops --set worker-pools.enabled=true
```

2. Download custom dataset by installing `hyperflow-dataset-stager` (Optional)

To execute a custom workflow download it into `hyperflow-engine` PersistentVolumeClaim using `hyperflow-dataset-stager`, which handles both creation of the PVC and downloading the data archive over Kubernetes Job. In later steps the NFS populated with data will be mounted into `hyperflow-engine` deployment `/work_dir` directory.

```bash
helm install -n hyperflow --dependency-update hf-dataset-stager-montage ./charts/hyperflow-dataset-stager
```

Pass following `values.yaml` to download workflow archive using `hyperflow-dataset-stager`:

```yaml
datasetStager:
  jobSpec:
    volumes:
    - name: workflow-data
        persistentVolumeClaim:
        claimName: nfs
    restartPolicy: "Never"
    containers:
    - name: injector
        image: <CUSTOM_IMAGE>
        volumeMounts:
        - name: workflow-data
            mountPath: "/work_dir"
        command:
        - "/bin/bash"
        - "-c"
        - >
            <WORKFLOW DOWNLOADING SCRIPT to /work_dir directory>
        resources:
        requests:
            memory: "64Mi"
            cpu: "250m"
```

3. Run workflow execution by installing `hyperflow-engine` helm chart


```bash
helm upgrade -n hyperflow --dependency-update -i hf-run-montage ./charts/hyperflow-run # remember to add --set hyperflow-nfs-volume.enabled=false if Persistant Volume Claim has been already created by hyperflow-dataset-stager helm release
```

#### Passing local files into `hyperflow-run` helm chart

* `Local directory to remote Kubernetes cluster`

Local directory can be copied into `hyperflow-engine` deployment using `kubectl cp`

```bash
$POD_NAME = (kubectl get pods -n hyperflow -l component=hyperflow-engine -o jsonpath='{.items[0].metadata.name}')
kubectl cp -n hyperflow <path-to-workflow-directory>/. $POD_NAME:/work_dir
```

* `Local directory to local Kubernetes cluster`

**DISCLAIMER**

When running local `kind` kubernetes cluster please **mount local directory into worker nodes** first

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
  labels: 
    hyperflow-wms/nodepool: hfmaster
    extraMounts:
      - hostPath: <WORKFLOW_LOCAL_DIRECTORY>
        containerPath: <WORKFLOW_WORKER_NODE_DIRECTORY>
- role: worker
  labels: 
    hyperflow-wms/nodepool: hfworker
    extraMounts:
      - hostPath: <WORKFLOW_LOCAL_DIRECTORY>
        containerPath: <WORKFLOW_WORKER_NODE_DIRECTORY>
- role: worker
  labels: 
    hyperflow-wms/nodepool: hfworker
    extraMounts:
      - hostPath: <WORKFLOW_LOCAL_DIRECTORY>
        containerPath: <WORKFLOW_WORKER_NODE_DIRECTORY>
```

The local directory can be mounted into a pod running on the same machine:

```yaml
hyperflow-engine:
  volumes:
    - name: config-map
      configMap:
        name: hyperflow-config
    - name: workflow-data
      hostPath:
        path: <WORKFLOW_WORKER_NODE_DIRECTORY>
    - name: worker-config
      configMap:
        name: worker-config
```

4. `ResourceQuota` (created by the chart — do not create it manually)

The Worker Pools Operator requires a namespace `ResourceQuota` (`hflow-requests`).
The `hyperflow-run` chart now creates it for you, scoped to worker pods via a
PriorityClass (`workerPools.resourceQuota` in its `values.yaml`). Do **not** also
run `kubectl create quota` — a second, unscoped quota would reject request-less
monitoring pods and break the operator's scaling metric (two `kube_resourcequota`
series). Just set `workerPools.resourceQuota.hard` to your worker-node capacity.
See [docs/worker-pools.md](docs/worker-pools.md).

5. Wait until all pods in workflow namespace are in running state

```bash
kubectl wait -n hyperflow --for=condition=available --timeout=1200s deployment --all
```

6. Begin sample workflow calculation


```bash
kubectl exec -n hyperflow -it deployment/hyperflow-engine -- sh -c 'hflow run /work_dir'
```

7. Cleanup

```bash
helm uninstall -n hyperflow hf-run-montage
helm uninstall -n hyperflow hf-ops
kubectl delete namespace hyperflow --force --grace-period=0
```