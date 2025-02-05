# Use Worker Pools to run a workflow

This example presents steps required to execute workflows using
**hybrid job-based and worker pools** model. This approach assumes running worker pools for
most numerous types of tasks (mProject, mDiffFit, mBackground), while remaining tasks are
executed as Kubernetes jobs.

## Prerequisites

* Cluster role bindings and node labels are properly configured in cluster (according to [instructions](../../README.md#running-the-workflow))
* NFS server is deployed in cluster and StorageClass is configured
* Used Hyperflow engine and job executor images must be compatible with worker pools model.

## Running the workflow

### Install Worker Pool Operator

Assuming you are in repository main directory, install the chart as follows:
```
helm install --values values/cluster/hyperflow-worker-pool-operator.yaml --namespace default worker-pool-operator charts/hyperflow-worker-pool-operator
```

### [Optional] Create workerpools namespace

```
kubectl create namespace workerpools
```

### Install Hyperflow charts

Assuming you are in repository main directory, install the chart as follows:
```
helm install nfs-pv charts/nfs-volume --namespace <namespace> --values values/cluster/nfs-volume.yaml
helm install redis charts/redis --namespace <namespace> --values values/cluster/redis.yml
helm install hyperflow-nfs-data --namespace <namespace> charts/hyperflow-nfs-data --values values/cluster/hyperflow-nfs-data.yaml
helm install hyperflow-engine --namespace <namespace> charts/hyperflow-engine --values values/cluster/hyperflow-engine.yaml
```

### Create ResourceQuota

Current implementation of Worker Pools Operator requires `ResourceQuota` object to be created
in the namespace where workflows are executed. Such an object is used in PrometheusRules to
obtain the maximum amount of resources designated to processing a workflow. Sample `ResourceQuota`
manifest is placed in [resourcequota.yml](resourcequota.yml) file. To create this resource, execute 
the following command Assuming you are in repository main directory):
```
kubectl create --namespace <namespace> -f examples/workerpools/resourcequota.yml
```
The `ResourceQuota` object should be adjusted to the total allocatable resources in the `hfworker` nodes. 
Resource limits does not need to be specified. 


### Create WorkerPool resources

Sample WorkerPool manifests for mProject, mDiffFit, mBackground are placed in [resources](resources) directory.
To create pools execute the following command (Assuming you are in repository main directory):
```
kubectl create --namespace <namespace> -f examples/workerpools/resources
```

Next, investigate whether the worker pools are properly initialized, by checking the `status`
field of the created resources. It should look like the following:

```
# Example command
kubectl --namespace <workerpools_namespace> describe wp mbackground mdifffit mproject | grep -E "^Status" -A 10
Status:
  Conditions:
    Message:         Worker pool is ready for processing workflows
    Reason:          WorkerPoolReady
    Status:          True
    Type:            Ready
    Message:         WorkerPool is being initialized
    Reason:          WorkerPoolInitializing
    Status:          False
    Type:            NotReady
  Worker Pool Name:  mbackground
--
Status:
  Conditions:
    Message:         Worker pool is ready for processing workflows
    Reason:          WorkerPoolReady
    Status:          True
    Type:            Ready
    Message:         WorkerPool is being initialized
    Reason:          WorkerPoolInitializing
    Status:          False
    Type:            NotReady
  Worker Pool Name:  mdifffit
--
Status:
  Conditions:
    Message:         Worker pool is ready for processing workflows
    Reason:          WorkerPoolReady
    Status:          True
    Type:            Ready
    Message:         WorkerPool is being initialized
    Reason:          WorkerPoolInitializing
    Status:          False
    Type:            NotReady
  Worker Pool Name:  mproject
```

You can also check, whether `Deployment`, `PrometheusRule` and `ScaledObject` resources were created for each pool. Example command:

```bash
kubectl --namespace <workerpools_namespace> get all,prometheusrules.monitoring.coreos.com,scaledobjects.keda.sh
```

In case of any mismatch, investigate operator pod logs.

### Configure Hyperflow engine

Create `workflow.config.executionModels.json` file in the `/work_dir` directory of the `hyperflow-engine` pod
with the following content:
```
[
  {
    "name": "mProject"
  },
  {
    "name": "mDiffFit"
  },
  {
    "name": "mBackground"
  }
]
```

### Execute the workflow

```bash
kubectl exec -it <hyperflow-engine-pod> sh

export RABBIT_HOSTNAME=rabbitmq.default # or your own rabbitmq url
cd /work_dir`
hflow run .
```



### Important notices

* If an error occurred during execution, all created queues must be manually purged or deleted in RabbitMQ, 
before starting subsequent workflow.  Hyperflow WMS does not implement queue deletion at the moment.

## Debugging

You can expose Prometheus and RabbitMQ GUIs using:
```
kubectl port-forward svc/monitoring-prometheus 9090:9090  
kubectl port-forward svc/rabbitmq 15672
```

Then open a browser and go to `http://localhost:9090` (Prometheus) and `http://localhost:15672` (RabbitMQ)

In Prometheus, you can check e.g. if the following query works:
```
rabbitmq_queue_messages_total{endpoint="rabbitmq-exporter"}
```
The full query used to calculate the desired number of replicas for HPA can be examined in the corresponding PrometheusRules objects, e.g.:
```
 kubectl get prometheusrules mproject -o yaml
```


