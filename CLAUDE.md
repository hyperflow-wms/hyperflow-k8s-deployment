## Running a sample workflow using HyperFlow

For subsequent kubernetes related actions i prefer to execute a helm or kubectl commands rather than using MCP server.

1. Create workerpools namespace

The namespace name must be unique in the kubernetes cluster. The subsequent commands must be executed within the same namespace.

```bash
kubectl create namespace hyperflow
```

2. Install `hyperflow-ops` helm chart

```bash
helm upgrade -n hyperflow --dependency-update -i hf-ops ./charts/hyperflow-ops --set worker-pools.enabled=true
```

3. Install `hyperflow-engine` helm chart

```bash
helm upgrade -n hyperflow --dependency-update -i hf-run-montage ./charts/hyperflow-run
```

### Running custom workflows 
The `hyperflow-engine` supports running custom workflows by downloading the workflow archives into `hyperflow-engine` deployment's `/work_dir` directory.

#### Supported workflow archive storages
* `AWS S3`

Provide following values to `hyperflow-run` helm chart to download workflow archive from AWS S3 using initContainers: 

```yaml
hyperflow-engine:
  initContainers:
    enabled: true
    dataInjector:
      enabled: true
      source:
        autoGenerateSecret: true
        s3:
          accessKey: "<AWS_IAM_ACCESS_KEY>"
          secretKey: "<AWS_IAM_ACCESS_SECRET_KEY>"
          bucket: "<AWS_S3_BUCKET_NAME>"
          filename: "<AWS_S3_BUCKET_FILENAME>"
    dataPreprocess:
        enabled: true
    
```

* `Remote storage`

Provide following values to `hyperflow-run` helm chart to download workflow archive from HTTP hosting using initContainers:

```yaml
hyperflow-engine:
  initContainers:
    enabled: true
    dataInjector:
        enabled: true
        image: <CUSTOM_IMAGE>
        volumeMounts:
        - name: workflow-data
          mountPath: "/work_dir"
        command:
        - "/bin/bash"
        - "-c"
        - >
            echo "data-injector: invoked";
            if [[ ! -f /work_dir/.dataInjectorFinished ]]; then
            echo "Cleaning /work_dir directory...";
            for f in /work_dir/*
            do
                rm -rf $f;
            done;

            <CUSTOM COMMAND TO DOWNLOAD WORKFLOW ARCHIVE to /work_dir/data.gz>

            touch /work_dir/.dataInjectorFinished
            else
            echo "File /work_dir/.dataInjectorFinished exists";
            echo "Downloading skipped.";
            fi;
            echo "data-injector: finished";
    dataPreprocess:
        enabled: true
```

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

4. Create `ResourceQuota` resources

The implementation of the Worker Pools Operator requires `ResourceQuota` to be present in the namespace.

```bash
kubectl create -n hyperflow quota hflow-requests --hard=requests.cpu=21,requests.memory=60Gi
```

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