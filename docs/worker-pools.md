# Worker Pools execution model

Hyperflow supports an advanced task execution model based on **autoscalable worker pools**. 
In this model, separate worker pools are created for most numerous types of tasks (e.g. mProject, mDiffFit, mBackground in Montage), while other tasks are usually executed as Kubernetes jobs (default execution
model).

<img src="img/worker-pool-model.svg" width="500">

The implementation is based on a custom [WorkerPool operator](https://github.com/hyperflow-wms/hyperflow-worker-pool-operator) which creates the worker pool deployments and other resources required for their autoscaling. The [Keda autoscaler](https://keda.sh) enables scaling of the worker pool deployments based on the length of their task queues (implemented using RabbitMQ) and also scaling them to zero. 

If multiple worker pools run simultaneously, they will scale within the available resource quota, proportionally to the lengths of their task queues (tasks with longer queues will get a larger chunk of the available resources).

## Running a sample workflow

### Create workerpools namespace

```
kubectl create namespace workerpools
```

### Install Helm charts

Worker pools are configured in the [values.yaml](../charts/hyperflow-run/values.yaml) of the `hyperflow-run` chart. Use preset
values to run a small Montage workflow. Make sure the `workerPools.enabled` flag is set to `true`.

Install the charts as follows (use `--namespace <namespace>` if using specific namespace):
```
cd hyperflow-k8s-deployment/charts
helm upgrade --dependency-update -n workerpools -i hf-ops hyperflow-ops
helm upgrade --dependency-update -n workerpools -i hf-run-montage hyperflow-run
```

### Create the ResourceQuota (scoped to worker pods)

The operator's PrometheusRules read a namespace `ResourceQuota` named
`hflow-requests` to learn the maximum resources available for processing a
workflow (it is the scaling ceiling). This object is a **manual prerequisite**:
the Helm charts do **not** create it — you apply it yourself, once, in the
namespace where you run the workflow.

A ready-to-apply manifest is provided at
[hflow-requests-quota.yaml](hflow-requests-quota.yaml) in this directory. Do
the following:

1. **Edit `spec.hard`** in that file to match the total allocatable cpu/memory
   of your worker nodes (the nodes labelled `hyperflow-wms/nodepool: hfworker`).
   The committed values (21 CPU / 60Gi) are only an example; resource limits
   need not be specified.
2. **Apply it** to your workflow namespace:
   ```bash
   kubectl apply -n workerpools -f docs/hflow-requests-quota.yaml
   ```

The manifest already carries a `scopeSelector` that limits the quota to worker
pods (which the operator chart tags with `priorityClassName: hyperflow-worker`;
the chart also ships that PriorityClass). This is what makes it safe to run the
quota in the same namespace as the monitoring stack: without the scope, a plain
quota on `requests.cpu`/`requests.memory` would reject every request-less pod —
including kube-prometheus-stack's cert-gen hook Job and the Prometheus server —
and would count control-plane pods against the worker ceiling. With the scope,
request-less monitoring pods schedule normally and only worker pods count. The
scaling rule reads only `kube_resourcequota{type="hard"}`, which scoping does
not change, so autoscaling is unaffected — see
[namespace-split-design.md](namespace-split-design.md) (Option C) for the full
rationale and validation.

### Configure the HyperFlow engine (execution models)

The engine decides which task types run on worker pools (rather than as plain
Kubernetes Jobs) via a `workflow.config.executionModels.json` file mounted at
`/work_dir`. When you deploy with the `hyperflow-run` chart this file is
**generated automatically** from the `workerPools.pools` list (see
`charts/hyperflow-run/templates/workerpools-cm.yml`) and mounted into the
engine — no manual step is needed.

Only if you run the engine outside the chart, create the file manually,
listing each worker-pool task type (content for the default Montage workflow;
otherwise adjust the task names):
```
kubectl exec -n workerpools -it deployment/hyperflow-engine -- sh -c 'cat > /work_dir/workflow.config.executionModels.json' <<EOF
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
kubectl exec -n workerpools -it deployment/hyperflow-engine -- sh -c 'hflow run /work_dir'
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


