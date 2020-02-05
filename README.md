# hyperflow-k8s-deployment
## gke-deployment

### Setting up the gke cluster 
If you are using desktop terminal, you need to configure gcloud to a certain project:
```sh
gcloud config set project <my-project>
```
Then start cluster creation using terraform with the following commands:
```sh
terraform init
terraform apply -auto-approve -var="gcp_project_id=<my-project>"
```

or if you're using Google Cloud Shell you can automatically get configured project id: 
```sh
terraform apply -auto-approve -var="gcp_project_id=${DEVSHELL_PROJECT_ID}"
```
Next connect to your cluster:
```sh
gcloud container clusters get-credentials standard-cluster-2 \
--zone europe-west4-a --project <my-project>
```
### Running the workflow
To run the workflow, use the following commands:
```sh
kubectl apply -f k8s
```
### Validating the workflow
To see if the example montage workflow run correctly, execute this command:
```sh
kubectl exec $(kubectl get pods --selector=name=hyperflow-engine --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}') /bin/ls work_dir | grep -i jpg
```
