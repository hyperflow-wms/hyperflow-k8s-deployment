#!/bin/bash
nodes=`kubectl get nodes -o go-template='{{range .items}}{{printf "%s\n" .metadata.name}}{{end}}'`

for node in $nodes; do
    if [[ $node =~ ^minikube-.*$ ]]; then
        kubectl label node $node nodetype=worker
    else
        kubectl label node $node nodetype=hfmaster
    fi
done