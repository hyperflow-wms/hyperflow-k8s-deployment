## Run on AWS EKS with AWS Academy
Create a new cluster using command:

```eksctl create cluster -f eks-aws-academy.yaml```

To update your `kubeconfig`, you can run command (`.aws/credentials` must be configured):

```
aws eks update-kubeconfig --region us-east-1 --name HfKlaster
```

**Notes:** 
- You need to change `instanceRoleARN` (in two places) and `serviceRoleARN`
- Make sure [`persistence`](https://github.com/hyperflow-wms/hyperflow-k8s-deployment/blob/c48e87bb61a5f92bb178dd53ba59ecbccc74fa06/charts/hyperflow-ops/values.yaml#L21) of the NFS provisioner is disabled (otherwise the provisioner will not start)

To experiment with different configurations, you might change the flavor and/or the number of nodes in the `HfWorkerNodes` group.
