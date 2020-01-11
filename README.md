# HyperFlow deployment on Kubernetes
## Architecture

<img src="https://github.com/hyperflow-wms/hyperflow-k8s-deployment/blob/master/hyperflow-k8s-arch.png" width="600">

## Running the workflow

Create Kubernetes resources as follows:
```
kubectl apply -f cm.yml
kubectl apply -f nfs-server-service.yml
kubectl apply -f redis-service.yml
kubectl apply -f nfs-server.yml
kubectl apply -f pv-pvc.yml
kubectl apply -f hyperflow-engine-deployment.yml
```

The default configuration runs a small Montage workflow. To change this, configure workflow *worker container* in `hyperflow-engine-deployment.yml` and *data container* in `nfs-server.yml`.

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
The `nfs` service is not properly resolved in the cluster because the resolution goes through the host DNS. You can fix this quickly by changing `nfs-server.default` to the IP address (`kubectl get services`) in the `pv-pvc.yml` file. Alternatively, you can configure the name resolution using `dmasq` as follows: 

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
options ndots:5
```
