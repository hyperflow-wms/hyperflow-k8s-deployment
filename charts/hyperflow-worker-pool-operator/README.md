# Hyperflow Worker Pool Operator helm chart

Worker Pool Operator is a Hyperflow extension, 
that unifies job executors management in execution models based on Worker Pools. 
Each Worker Pool consists of several Kubernetes resources, like `Deployment`, `PrometheusRule` and `HorizontalPodAutoscalers`.
This chart is intended to facilitate creation, updating and deletion of those objects based on `WorkerPool` custom resource.
This chart also configures all external components that are required to autoscale Worker Pools deployments
based on various metrics.

## Getting started

Install manifest with helm:
```
helm install --namespace default worker-pool-operator .
```
Uninstall:
```
helm uninstall --namespace default worker-pool-operator
```
### Chart parameters:

| Name                                   | Description                                                                                                                                                                                                                     | Value                                  |
|----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------|
| `nodeSelector`                         | Node selector for `hyperflow-worker-pool-operator` deployment                                                                                                                                                                   | `{}`                                   |
| `image`                                | Image for `hyperflow-worker-pool-operator` deployment                                                                                                                                                                           | `kjanecki/hflow-worker-operator:1.0.0` |
| `config.data`                          | Content of ConfigMap with templates for Worker Pool child resources. Should contain the following templates: `deployment.yml`, `prometheus-rule.yml`, `scaledobject.yml`. If not provided, the default templates will be used.  | lookup in `values.yaml`                |                               
| `kube-prometheus-stack.enabled`        | Whether kube-prometheus-stack chart should be deployed                                                                                                                                                                          | `false`                                |    
| `prometheus-adapter.enabled`           | Whether prometheus-adapter chart should be deployed                                                                                                                                                                             | `false`                                |    
| `rabbitmq.enabled`                     | Whether rabbitmq chart should be deployed                                                                                                                                                                                       | `false`                                |    
| `prometheus-rabbitmq-exporter.enabled` | Whether prometheus-rabbitmq-exporter chart should be deployed                                                                                                                                                                   | `false`                                |    
| `keda.enabled`                         | Whether prometheus-adapter chart should be deployed                                                                                                                                                                             | `false`                                |    

Other parameters are set according to dependent charts. Note that if you want to deploy pods on specific nodes, you have to override
the nodeSelector field in every dependent chart.

Example settings are presented on `/values/cluster/hyperflow-worker-pool-operator.yaml` path in the repository root.

### Chart dependencies:
| Chart name                     | Repository URL                                      | Use case                                                               |
|--------------------------------|-----------------------------------------------------|------------------------------------------------------------------------|
| `kube-prometheus-stack`        | https://prometheus-community.github.io/helm-charts  | Collect and expose metrics for Worker Pool autoscalers                 |
| `prometheus-adapter`           | https://prometheus-community.github.io/helm-charts  | Register Prometheus-based custom metrics for HPA                       |
| `rabbitmq`                     | https://charts.bitnami.com/bitnami                  | Transfer job commands between Hyperflow engine and job executors       |
| `prometheus-rabbitmq-exporter` | https://prometheus-community.github.io/helm-charts  | Expose additional RabbitMQ metrics like individual queue message count |
| `keda`                         | https://kedacore.github.io/charts                   | Manage HPA and provide ability to scale to zero                        |

### Create WorkerPool resources

Current implementation of Operator uses `ResourceQuota` to control the maximum amount of allocatable resources, so ensure that a `ResourceQuota` object is created in target namespace. After creating `ResourceQuta` you can create `WorkerPool` resources.

Example WorkerPool manifest:
```
apiVersion: hyperflow.agh.edu.pl/v1
kind: WorkerPool
metadata:
  name: mproject
spec:
  taskType: mProject
  image: kjanecki/montage2-amqp:latest
  rabbitHostname: rabbitmq.default
  prometheusUrl: http://monitoring-prometheus.default:9090
  redisUrl: redis://redis:6379
  minReplicaCount: 0
  maxReplicaCount: 50
  initialResources:
    requests:
      cpu: "0.5"
      memory: "524288000"
    limits:
      cpu: "0.5"
      memory: "524288000"
```

## WorkerPool Custom Resource reference

| Name                                    | Description                                                              |
|-----------------------------------------|--------------------------------------------------------------------------|
| `spec.taskType`                         | The name of type of task in lowerCamelCase (e.g. `mProject`)             |
| `spec.image`                            | Job executor container image                                             |
| `spec.rabbitHostname`                   | RabbitMQ service hostname (e.g. `rabbitmq.default`)                      |
| `spec.prometheusUrl`                    | URL of Prometheus server (e.g.  `http://prometheus:9090`)                |
| `spec.redisUrl`                         | URL of Redis database (e.g. `redis://redis:6379`)                        |
| `spec.minReplicaCount`                  | [Optional] Minimum replication count for HPA. Defaults to 0              |
| `spec.maxReplicaCount`                  | [Optional] Maximum replication count for HPA. Defaults to 50             |
| `spec.initialResources.requests.cpu`    | CPU request for Worker Pool pods. Must be specified in vCPUs             |
| `spec.initialResources.requests.memory` | Memory request for Worker Pool pods. Must be specified in bytes          |
| `spec.initialResources.limits.cpu`      | [Optional] CPU limit for Worker Pool pods. Must be specified in vCPUs    |
| `spec.initialResources.limits.memory`   | [Optional] Memory limit for Worker Pool pods. Must be specified in bytes |

### Configure Hyperflow engine for worker pools

Hyperflow engine controls execution model with optional config file `workflow.config.executionModels.json` 
that can be created in `/work_dir` directory. By default, Hyperflow executes tasks using job-based execution model.
Adding a record with the `name` parameter set with the type of tasks to the `workflow.config.executionModels.json`
will override this setting and change the execution model to worker pools. Optional `queue` parameter
is also available to override the name of the queue (default: <namespace>.<task_type_name>)

Example `workflow.config.executionModels.json` that configure Hyperflow engine to run worker pools
for mProject, mDiffFit and mBackground tasks:
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

## Troubleshooting

After creation or update of any `WorkerPool` object, the Worker Pool Operator updates the `status` of processed resource. 
Successful initialization of WorkerPool results in the following conditions:
```
status:
  conditions:
  - message: Worker pool is ready for processing workflows
    reason: WorkerPoolReady
    status: "True"
    type: Ready
  - message: WorkerPool is being initialized
    reason: WorkerPoolInitializing
    status: "False"
    type: NotReady
```

After successful initialization, a single instance of every of the following K8s API should be created: `deployment.apps`, `prometheusrules.monitoring.coreos.com`, `scaledobjects.keda.sh`.
The names of the listed resources defaults to the name of `WorkerPool` object. If any of the listed object is not present,
it means that an error occurred during initialization. The errors, along with the description, are also included in the `status` field. 
You may also investigate the logs of Worker Pool Operator pods.
 
