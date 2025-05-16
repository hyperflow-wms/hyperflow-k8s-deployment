# Worker Pools execution model

Hyperflow supports an advanced task execution model based on **autoscalable worker pools**. 
In this model, separate worker pools are created for most numerous types of tasks (e.g. mProject, mDiffFit, mBackground in Montage), while other tasks are usually executed as Kubernetes jobs (default execution
model).

<img src="https://github.com/hyperflow-wms/hyperflow-k8s-deployment/blob/master/examples/workerpools/worker-pool-model.svg" width="500">

The implementation is based on a custom [WorkerPool operator](https://github.com/hyperflow-wms/hyperflow-worker-pool-operator) which creates the worker pool deployments and other resources required for their autoscaling. The [Keda autoscaler](https://keda.sh) enables scaling of the worker pool deployments based on the length of their task queues (implemented using RabbitMQ) and also scaling them to zero. 

If multiple worker pools run simultaneously, they will scale within the available resource quota, proportionally to the lengths of their task queues (tasks with longer queues will get a larger chunk of the available resources).

## Running a sample workflow

### [Optional] Create workerpools namespace

```
kubectl create namespace workerpools
```

### Clone repositories with Helm charts

```
git clone https://github.com/hyperflow-wms/hyperflow-k8s-deployment
git clone https://github.com/hyperflow-wms/hyperflow-worker-pool-operator
```

### Install Helm charts

Worker pools are configured in the [values.yaml](https://github.com/hyperflow-wms/hyperflow-k8s-deployment/blob/master/charts/hyperflow-run/values.yaml) of the `hyperflow-run` chart. Use preset
values to run a small Montage workflow. Make sure the `workerPools.enabled` flag is set to `true`.

Install the charts as follows (use `--namespace <namespace>` if using specific namespace):
```
cd hyperflow-k8s-deployment/charts
helm upgrade --dependency-update -i hf-ops hyperflow-ops
helm upgrade --dependency-update -i hf-run-montage hyperflow-run
```

### Create ResourceQuota

The implementation of the Worker Pools Operator requires `ResourceQuota` object to be created
in the namespace where workflows are executed. Such an object is used in PrometheusRules to
obtain the maximum amount of resources designated to processing a workflow. Currently this step is done manually. A sample `ResourceQuota` manifest is placed in [resourcequota.yml](resourcequota.yml) file. To create this resource, execute the following command Assuming you are in repository main directory):
```
kubectl create --namespace <namespace> -f examples/workerpools/resourcequota.yml
```
The `ResourceQuota` object should be adjusted to the total allocatable resources in the worker nodes used to
run workflow tasks (labelled `hyperflow-wms/nodepool: hfworker`). 
Resource limits do not need to be specified. 

### Configure Hyperflow engine

Create `workflow.config.executionModels.json` file in the `/work_dir` directory of the `hyperflow-engine` pod
using the following command (content for the default workflow, otherwise adjust the task names):
```
cat > workflow.config.executionModels.json << EOF
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
EOF
```

### Execute the workflow
The workflow needs to be started manually in the Hyperflow engine Pod:
```bash
kubectl exec -it <hyperflow-engine-pod> -- sh

cd /work_dir`
hflow run .
```

### Cleanup - important

If an error occurred during execution, all created queues must be manually purged or deleted in RabbitMQ, 
before starting subsequent workflow.  Hyperflow WMS does not implement queue deletion at the moment.


## Monitoring and debugging
### Watching worker pool deployments
You can observe how worker pools scale up and down by watching their deployments:
```
kubectl get deploy [-n <workerpools_namespace>] -w
```

### Examining WorkerPool resources

You can investigate whether the worker pools are properly initialized by checking the `status`
field of the created resources, for example:

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

You can also check, whether `Deployment`, `PrometheusRule` and `ScaledObject` resources were created for each pool:

```bash
kubectl [--namespace <workerpools_namespace>] get all,prometheusrules.monitoring.coreos.com,scaledobjects.keda.sh
```

In case of any problem, investigate operator pod logs.


### Using Prometheus and RabbitMQ web GUIs

You can connect to Prometheus and RabbitMQ GUIs, e.g., to check if RabbitMQ queue metrics are visible and queries work. To this end, you need to forward the ports:
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


