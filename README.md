# HyperFlow deployment on Kubernetes
## Architecture

<img src="https://github.com/hyperflow-wms/hyperflow-k8s-deployment/blob/master/hyperflow-k8s-arch.png" width="600">

## Running the workflow

### Granting HyperFlow permission to create jobs
To allow the HyperFlow process to create new Pods, you need to grant admin access to its service account. For now the workaround is to grant super-user access to all service accounts cluster-wide: 
```
kubectl create clusterrolebinding serviceaccounts-cluster-admin \
--clusterrole=cluster-admin \
--group=system:serviceaccounts
```

### Creating Kubernetes resources
Create Kubernetes resources as follows:

```
kubectl kustomize base | kubectl apply -f -
```
The default configuration (`base` folder) runs a small Montage workflow. To change this, configure workflow *worker container* in `base/hyperflow-engine-deployment.yml` and *data container* in `base/nfs-server.yml`, or use prepared [kustomize](https://github.com/kubernetes-sigs/kustomize) overlays as follows:

```
kubectl kustomize overlays/soykb | kubectl apply -f -
```


## Running without the data container
Coming soon...

## Configuring bare-metal Kubernetes installation
To properly configure a bare-metal Kubernetes installation (e.g. minikube) for a HyperFlow+nfs deployment, you need to do the following steps (commands for Ubuntu 18.04).

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

