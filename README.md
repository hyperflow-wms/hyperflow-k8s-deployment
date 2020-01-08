# HyperFlow deployment on Kubernetes
## Architecture

<img src="https://github.com/hyperflow-wms/hyperflow-k8s-deployment/blob/master/hypeflow-k8s-arch.png" width="600">

## Running the workflow

Create Kubernetes resources as follows:
```
kubectl apply -f cm.yml
kubectl apply -f nfs-server.yml
kubectl apply -f nfs-server-service.yml
kubectl apply -f pv-pvc.yml
kubectl apply -f hyperflow-engine-deployment.yml
kubectl apply -f redis-service.yml
```

The default configuration runs a small Montage workflow. To change this, configure workflow *worker container* in `hyperflow-engine-deployment.yml` and *data container* in `nfs-server.yml`.

## Running without the data container
