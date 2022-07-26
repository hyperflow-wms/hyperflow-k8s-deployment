# HyperFlow deployment on Kubernetes
## Architecture

<img src="https://github.com/hyperflow-wms/hyperflow-k8s-deployment/blob/master/hyperflow-k8s-arch.png" width="600">

## Preparing the workflow
### Workflow graph
You need to provide the workflow graph as HyperFlow `workflow.json` file. This file needs to be uploaded to the working directory in the HyperFlow engine container (default location: `/work_dir`) before running the workflow. However, there are *workflow data containers* that already contain `workflow.json`, so you don't have to do anything if you use them (see below). 


### Workflow function
To run workflows in a Kubernetes cluster, workflow tasks in `workflow.json` must use the `k8sCommand` function. It is recommended to use variable in `workflow.json` as follows:

```
function: {{function}}
```
The value of the `{{function}}` variable can be set via `HF_VAR_function=k8sCommand` environment variable. This is automatically done in `hyperflow-engine-deployment.yml`. 

### Configuration of Docker images
To run a workflow, you need to provide the following Docker images:
* *Worker image*: contains workflow software and HyperFlow [job executor](https://github.com/hyperflow-wms/hyperflow-job-executor). This image can be set via the `HF_VAR_WORKER_CONTAINER` environment variable in `hyperflow-engine-deployment.yml`. See *Job template configuration* for an alternative way.  
* *Data image*: contains workflow data which is copied to a shared NFS volume which is the working directory where jobs are run (default `/work_dir`). This image is set in the `workflow-data` container in `nfs-server.yml`.

 
#### Preparing container images
You can find examples of Dockerfiles for worker and data containers in workflow repositories: [Montage](https://github.com/hyperflow-wms/montage-workflow), [Montage2](https://github.com/hyperflow-wms/montage2-workflow), [Soykb](https://github.com/hyperflow-wms/soykb-workflow). You can prepare your data containers and generate workflow graphs using workflow generators provided in some workflow repositories. 

#### Running without data container
To run the workflow without data container, you can set up an empty container and upload workflow data there before running the workflow. More instructions coming soon...


#### Ready-to-use images

[Montage](https://github.com/hyperflow-wms/montage-workflow)
* Worker container: `hyperflowwms/montage-worker`
* Data containers: `matplinta/montage-workflow-data:degree0.25` (very small, good for testing)

[Montage2](https://github.com/hyperflow-wms/montage2-workflow)
* Worker container: `hyperflowwms/montage2-worker`
* Data containers: `hyperflowwms/montage2-workflow-data:montage2-2mass-025-latest` (small, 619 jobs), `matplinta/montage2-workflow-data:degree1.0` (large, 4846 jobs), `hyperflowwms/montage2-workflow-data:montage2-2mass-3.0-latest` (very large, 16444 jobs), `hyperflowwms/montage2-workflow-data:montage2-dss-3.0-latest` (very large, 31768 jobs)

[Soykb](https://github.com/hyperflow-wms/soykb-workflow)
* Worker container: `hyperflowwms/soykb-worker` 
* Data containers: `hyperflowwms/soykb-workflow-data:hyperflow-soykb-example-f6f69d6ca3ebd9fe2458804b59b4ef71` (small, 53 jobs)


### Job template configuration
Workflow tasks are run as Kubernetes Jobs specified by `job-template.yml`, a file which is currently defined as config-map `cm.yml`. The job template contains parameters whose values are set by variables `${var}`, for example:
  * `containerName`: Docker container image to be used to run the task (globally configured through `HF_VAR_WORKER_CONTAINER` variable in `hyperflow-engine-deployment.yml`)
  * `cpuRequest`: CPU [resource request](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers) for this job (default value: `0.5`)
  * `memRequest`: Memory [resource request](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers) for this job (default value: `50Mi`)
  * `volumePath`: path to the working directory where input data for the job is provided (default value: `/work_dir`)

These variables have default values, but you can override them follows:

* By providing `workflow.config.jobvars.json` file, e.g.
```
{
  "containerName": "myWorkerContainer"
}
```
* Some parameters can be set in workflow task definitions (`context.executor`) in `workflow.json`. This allows for per-task configuration of some variables:
  * `image`: sets `containerName` for the task
  * `cpuRequest`: sets `cpuRequest` for the task 
  * `memRequest`: sets `memRequest` for the task
  
Note that all job variables have default values which will be used if not overridden.  

  
## Running the workflow

### Setting up the cluster the Helm way

Firstly, make sure your k8s context and namespaces point to right cluster.

There are several details you should know before installing Hyperflow on your cluster:

#### Cluster role bindings
To allow the HyperFlow Engine Pod to create new Pods, you need to grant admin access to its service account. For now the workaround is to grant super-user access to all service accounts cluster-wide: 
```
kubectl create clusterrolebinding serviceaccounts-cluster-admin \
--clusterrole=cluster-admin \
--group=system:serviceaccounts
```

This is included in `hyperflow-engine` chart and is applied automatically when it is installed.

#### Node labels
HyperFlow Kubernetes resources use the following [`nodeSelectors`](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector):
* `nodetype: hfmaster` for all HyperFlow master components (Hyperflow engine deployment, Redis server, NFS server)
* `nodetype: worker` for workflow job Pods

Consequently, it is recommended to set up two pools in your cluster:
* A *master* pool: 1 node with label `nodetype: hfmaster` -- for master components.
* A *worker* pool: any number of nodes with label `nodetype: worker` -- for workflow jobs. 
This way jobs won't interfere with workflow runtime components.

If you don't want to use labels, you can use values from `minikube` directory that don't use selectors.  


### Installing resources
Assuming you are in repository main directory, install Kubernetes resources as follows:
```
helm install nfs-server-provisioner charts/nfs-ganesha-server-and-external-provisioner/charts/nfs-server-provisioner --values values/cluster/nfs-server-provisioner.yml
helm install nfs-pv charts/nfs-volume --values values/cluster/nfs-volume.yaml
helm install redis charts/redis --values values/cluster/redis.yml
helm install hyperflow-nfs-data charts/hyperflow-nfs-data --values values/cluster/hyperflow-nfs-data.yaml
helm install hyperflow-engine charts/hyperflow-engine --values values/cluster/hyperflow-engine.yaml
```

The `hyperflow-nfs-data` Helm Chart populates the NFS volume with initial data of small Montage2 workflow.
To change this, configure the chart by setting `workflow.image` property in file `values/cluster/hyperflow-nfs-data.yaml`.
You can use images described in [Ready-to-use images section](#ready-to-use-images).

Once all pods are up and running or completed, you can manually run the workflow as follows:
* `kubectl exec -it <hyperflow-engine-pod> sh`
* `cd /work_dir`
* `hflow run .`

## Using Google Kubernetes Engine

Here are additional steps you need to do in order to run HyperFlow on the Google Kubernetes Engine.

### Configure `gcloud` and create Kubernetes cluster

- Install the `gcloud` client as described [here](https://cloud.google.com/sdk/install).
- If needed, [create a new project](https://cloud.google.com/resource-manager/docs/creating-managing-projects) using the Google cloud console.
- Create the Kubernetes cluster with the following command (fill in the `project id`):
```
gcloud container clusters create --project=<your project id> --zone=europe-west2-a --num-nodes=4 --cluster-version=1.15.8-gke.2 --machine-type=n1-standard-2 my-k8s-cluster
```
- [Install `kubectl`](https://kubernetes.io/docs/tasks/tools/install-kubectl/) and configure `kubeconfig` to access your GKE cluster [following these instructions](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#generate_kubeconfig_entry).

### Resize the cluster

To minimize cost, you can delete the cluster when not used (e.g. from the console). However, it may be more convenient to just spin it down to 0 as follows:

```
gcloud container clusters resize my-k8s-cluster --node-pool default-pool --num-nodes=0
```
This command can also be used to resize the cluster to the desired number of nodes.


## Configuring bare-metal Kubernetes installation
To properly configure a bare-metal Kubernetes installation (e.g. [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube)) for a HyperFlow+nfs deployment, you need to do the following steps (commands for Ubuntu 18.04).

### Install packages
```
apt install nfs-kernel-server
apt install dnsmasq
```

### Configure NFS service resolution
The `nfs` service is not properly resolved in the cluster because the resolution goes through the host DNS. You can fix this quickly by changing `nfs-server.default` to the IP address (`kubectl get services`) in the `pv-pvc.yml` file. Alternatively, you can configure the name resolution using `dnsmasq` as follows: 

- Add the following to `/etc/dnsmasq.conf`: 
```
server=/cluster.local/10.96.0.10
server=8.8.8.8
listen-address=127.0.0.1
```
- Run this to add an entry to `/etc/hosts`:
```
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts 
```
- Add these lines to `/etc/resolv.conf`:
```
search svc.cluster.local
options ndots:5 timeout:1
```
## Processing logs
After the workflow has finished, you can process its logs by starting the following Kubernetes job:
```
helm upgrade --install parser charts/parser --values values/cluster/parser.yml
```
This will create a number of `jsonl` (JSON lines format) files in directory `/work_dir/parsed/<workflow_dir>`. The structure of these files is documented [here](https://github.com/hyperflow-wms/log-parser). 

## Visualization of workflow execution trace
To generate a visualization of the workflow execution, first you need to generate the processed logs (see above), then run this Kubernetes job:
```
helm upgrade --install viz-trace charts/viz-trace --values values/cluster/viz-trace.yaml
```
This generates a `png` file in each `/work_dir/parsed/<workflow_dir>` directory.

## Configuration of two kubernetes clusters
To run workflow on two kubernetes clusters, you can set them up on aws using [eksctl](https://eksctl.io/) command.
```
eksctl create cluster -f cloud/aws-private.yaml
eksctl create cluster -f cloud/aws-public.yaml
```
To avoid exposing services with a public ip address, you can set up [VPC peering](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html) 
according to this [guide](https://blog.couchbase.com/kubernetes-vpc-peering/).

- Then, in private cluster install redis as follows:
```
helm install redis bitnami/redis --values values/cluster/redis-cloud.yaml
```

- Set up [juicefs object storage](https://juicefs.com/docs/community/how_to_setup_object_storage/) in
`values/cluster/juicefs.yaml` file with one of available storage options and set up corresponding node labels followed by:
```
helm install juicefs-csi-driver juicefs-csi-driver/juicefs-csi-driver --values values/cluster/juicefs.yaml -n kube-system
helm install juicefs-pv charts/juicefs-pv --values values/cluster/juicefs-pv.yaml
helm install hyperflow-engine charts/hyperflow-engine --values values/cluster/hyperflow-engine.yaml
```
In order to get access to the public cluster from private cluster you can use [script](https://github.com/gravitational/teleport/blob/master/examples/gke-auth/get-kubeconfig.sh)
to generate kubeconfig which can be used in private cluster.
- Then, in public cluster run the following commands:
```
helm install juicefs-csi-driver juicefs-csi-driver/juicefs-csi-driver --values values/cluster/juicefs.yaml -n kube-system
helm install juicefs-pv charts/juicefs-pv --values values/cluster/juicefs-pv.yaml
kubectl create clusterrolebinding serviceaccounts-cluster-admin --clusterrole=cluster-admin --group=system:serviceaccounts
```
Next, you can use [hflow-tools](https://github.com/hyperflow-wms/hflow-tools#hflow-metis) to partition a workflow.