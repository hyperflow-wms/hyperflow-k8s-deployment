#!/bin/bash
nodes=`kubectl get nodes -o go-template='{{range .items}}{{printf "%s\n" .metadata.name}}{{end}}'`

kubectl taint nodes kind-control-plane node-role.kubernetes.io/master-

for node in $nodes; do
    if [[ $node =~ ^kind-worker.*$ ]]; then
        kubectl label node $node nodetype=worker
    else
        kubectl label node $node nodetype=hfmaster
    fi
done