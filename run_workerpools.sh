#!/usr/bin/env bash
set -x
set -e
WORKFLOW_DATA_MONTAGE2_0_25="hyperflowwms/montage2-workflow-data:montage2-2mass-025-latest"
WORKFLOW_DATA_MONTAGE2_1_0="matplinta/montage2-workflow-data:degree1.0"
WORKFLOW_DATA_MONTAGE2_3_0="hyperflowwms/montage2-workflow-data:montage2-2mass-3.0-latest"
WORKFLOW_DATA_MONTAGE2_3_0_LARGEST="hyperflowwms/montage2-workflow-data:montage2-dss-3.0-latest"
WORKFLOW_DATA_1000GENOME="hyperflowwms/1000genome-workflow-data:data20130502-latest"
WORKFLOW_DATA_SOYKB="hyperflow-soykb-example-latest"
WORKFLOW_DATA_HECIL_SMALL="macsko/hecil-workflow-data:hecil_small-latest"
WORKFLOW_DATA_HECIL_MEDIUM="macsko/hecil-workflow-data:hecil_medium-latest"
WORKFLOW_DATA_HECIL_MEDIUM_SMALL="macsko/hecil-workflow-data:hecil_medium_small-latest"

WORKFLOW_WORKER_MONTAGE2="hyperflowwms/montage2-worker:je-1.3.2"
WORKFLOW_WORKER_1000GENOME="hyperflowwms/1000genome-worker"
WORKFLOW_WORKER_HECIL="macsko/hecil-worker:je-1.3.4"
# WORKFLOW_WORKER_HECIL="hyperflowwms/hecil-worker:latest"
WORKFLOW_WORKER_SOYKB="macsko/soykb-worker:je-1.3.4"

WORKFLOW_NAME_MONTAGE2="montage2"
WORKFLOW_NAME_HECIL="hecil"

# Script options
create_gke_cluster=0
build_hyperflow_cluster=0
run_hyperflow_workflow=0
fetch_metrics_img=0
delete_gke_cluster=0
purge_workflow_data=0
vpa_enabled=0
vpa_option=""

# Cluster options
project_name="magisterka-418221"
# project_name="mgrs-425106"
cluster_name="hyperflow-cluster"
machine_type="c3.xmedium"
num_nodes="10"
disk_size="100" # 100
zone="us-central1-c"
custom_disk=1

# Config options
workflow_data=$WORKFLOW_DATA_MONTAGE2_0_25
workflow_worker=$WORKFLOW_WORKER_MONTAGE2
workflow_name=$WORKFLOW_NAME_MONTAGE2
workerRequestsCpu="0.25" # 0.1 # 0.25 # 1.0
workerRequestsMem="262144000" # 102400000 # 262144000 # 1048576000
quotaRequestsCpu="60" # 6 # 15 # 25 # 50
quotaRequestsMem="120Gi" # 12 # 25Gi # 100 # 200
vpa_opt="opt9" # Only for result dir

workflow_selected=""
nodes_size_selected=""
requests_selected=""

while test $# -gt 0; do case $1 in
-c | --create_cluster )
    create_gke_cluster=1
    ;;
-b | --build_hyperflow )
    build_hyperflow_cluster=1
    ;;
-s | --start_workflow )
    run_hyperflow_workflow=1
    ;;
-f | --fetch_metrics )
    fetch_metrics_img=1
    ;;
-d | --delete_cluster )
    delete_gke_cluster=1
    ;;
-p | --purge_data )
    purge_workflow_data=1
    ;;
-i | --vpa_initial )
    vpa_enabled=1
    vpa_option="Initial"
    ;;
-r | --vpa_recreated )
    vpa_enabled=1
    vpa_option="Recreate"
    ;;
-w | --workflow )
    shift
    workflow_selected=$1
    ;;
-n | --nodes_size )
    shift
    nodes_size_selected=$1
    ;;
-q | --requests )
    shift
    requests_selected=$1
    ;;
esac; shift; done

if [[ $workflow_selected = "m025" ]]; then
    workflow_data=$WORKFLOW_DATA_MONTAGE2_0_25
    workflow_worker=$WORKFLOW_WORKER_MONTAGE2
    workflow_name=$WORKFLOW_NAME_MONTAGE2
elif [[ $workflow_selected = "m10" ]]; then
    workflow_data=$WORKFLOW_DATA_MONTAGE2_1_0
    workflow_worker=$WORKFLOW_WORKER_MONTAGE2
    workflow_name=$WORKFLOW_NAME_MONTAGE2
elif [[ $workflow_selected = "m30" ]]; then
    workflow_data=$WORKFLOW_DATA_MONTAGE2_3_0
    workflow_worker=$WORKFLOW_WORKER_MONTAGE2
    workflow_name=$WORKFLOW_NAME_MONTAGE2
elif [[ $workflow_selected = "hm" ]]; then
    workflow_data=$WORKFLOW_DATA_HECIL_MEDIUM
    workflow_worker=$WORKFLOW_WORKER_HECIL
    workflow_name=$WORKFLOW_NAME_HECIL
fi

if [[ $nodes_size_selected = "large9" ]]; then
    machine_type="e2-standard-8"
    num_nodes="9"
    quotaRequestsCpu="60"
    quotaRequestsMem="120Gi"
elif [[ $nodes_size_selected = "large5" ]]; then
    machine_type="e2-standard-8"
    num_nodes="5"
    quotaRequestsCpu="30"
    quotaRequestsMem="60Gi"
elif [[ $nodes_size_selected = "medium5" ]]; then
    machine_type="e2-standard-4"
    num_nodes="5"
    quotaRequestsCpu="15"
    quotaRequestsMem="30Gi"
elif [[ $nodes_size_selected = "medium3" ]]; then
    machine_type="e2-standard-4"
    num_nodes="3"
    quotaRequestsCpu="6"
    quotaRequestsMem="12Gi"
fi

if [[ $requests_selected = "250" ]]; then
    workerRequestsCpu="0.25"
    workerRequestsMem="262144000"
elif [[ $requests_selected = "1000" ]]; then
    workerRequestsCpu="1.0"
    workerRequestsMem="1048576000"
fi

create_cluster() {
    # 1.28.7-gke.1026000
    # 1.28.8-gke.1095000
    gcloud beta container --project $project_name clusters create $cluster_name --no-enable-basic-auth --cluster-version "1.28.9-gke.1209000" --release-channel "regular" --machine-type $machine_type --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size $disk_size --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes $num_nodes --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/$project_name/global/networks/default" --subnetwork "projects/$project_name/regions/us-central1/subnetworks/default" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --security-posture=standard --workload-vulnerability-scanning=disabled --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --binauthz-evaluation-mode=DISABLED --enable-managed-prometheus --enable-shielded-nodes --node-locations $zone --zone $zone
}

connect_cluster() {
    gcloud container clusters get-credentials $cluster_name --zone $zone --project $project_name
}

create_custom_disk() {
    gcloud compute disks create data-hf-ops-nfs-server-provisioner-0 \
    --project=$project_name \
    --type=pd-balanced \
    --size=100GB \
    --zone=$zone
}

delete_cluster() {
    gcloud container --project $project_name clusters delete $cluster_name --zone $zone -q
}

delete_custom_disk() {
    gcloud compute disks delete data-hf-ops-nfs-server-provisioner-0 --project $project_name --zone $zone -q
}

purge_data() {
    engine_pod_name="$(kubectl get pods -n workerpools --no-headers -o custom-columns=":metadata.name" | grep hyperflow-engine)"
    kubectl -n workerpools exec -it $engine_pod_name -- sh -c 'rm -r /work_dir/*'
    kubectl -n workerpools exec -it $engine_pod_name -- sh -c 'rm -r /work_dir/*'
    
    # helm install $workflow_name-workers --namespace workerpools workflow_charts/$workflow_name/resources --values workflow_charts/$workflow_name/resources/values.yaml --set workerRequests.cpu=\"$workerRequestsCpu\",workerRequests.memory=\"$workerRequestsMem\",quotaRequests.cpu=\"$quotaRequestsCpu\",quotaRequests.memory=\"$quotaRequestsMem\"

    # if [[ $vpa_enabled == 1 ]]; then
    #     helm uninstall $workflow_name-vpa --namespace workerpools
    #     helm install $workflow_name-vpa --namespace workerpools workflow_charts/$workflow_name/vpa --values workflow_charts/$workflow_name/vpa/values.yaml --set updateMode=$vpa_option
    # fi

    helm uninstall hyperflow-nfs-data parser viz-trace --namespace workerpools
    helm install hyperflow-nfs-data --namespace workerpools charts/hyperflow-nfs-data --values values/cluster/hyperflow-nfs-data.yaml --set workflow.image=$workflow_data
    kubectl wait --for=condition=complete -n workerpools job/nfs-data --timeout=1h
}

build_hyperflow() {
    eval "$(kubectl get nodes -lkubernetes.io/role=standard --no-headers | awk 'NR==1{print "kubectl label nodes " $1 " hyperflow-wms/nodepool=hfmaster"}NR>1{print "kubectl label nodes " $1 " hyperflow-wms/nodepool=hfworker"}')"
    
    kubectl create clusterrolebinding serviceaccounts-cluster-admin \
        --clusterrole=cluster-admin \
        --group=system:serviceaccounts
    helm upgrade --dependency-update -i hf-ops charts/hyperflow-ops
    #helm upgrade --create-namespace --namespace hyperflow-ops --dependency-update -i hf-ops charts/hyperflow-ops

    # if [[ $custom_disk == 1 ]]; then
    #     kubectl apply -f pv.yaml
    #     echo "Waiting for PV to be running..."
    #     kubectl wait --for=condition=Ready pod/hf-ops-nfs-server-provisioner-0 --timeout=1h
    # fi
    
    kubectl create namespace workerpools
    helm install nfs-pv charts/nfs-volume --namespace workerpools --values values/cluster/nfs-volume.yaml
    helm install redis charts/redis --namespace workerpools --values values/cluster/redis.yml
    helm install hyperflow-nfs-data --namespace workerpools charts/hyperflow-nfs-data --values values/cluster/hyperflow-nfs-data.yaml --set workflow.image=$workflow_data
    helm install hyperflow-engine --namespace workerpools charts/hyperflow-engine --values values/cluster/hyperflow-engine.yaml --set containers.worker.image=$workflow_worker
    helm install $workflow_name-workers --namespace workerpools workflow_charts/$workflow_name/resources --values workflow_charts/$workflow_name/resources/values.yaml --set workerRequests.cpu=\"$workerRequestsCpu\",workerRequests.memory=\"$workerRequestsMem\",quotaRequests.cpu=\"$quotaRequestsCpu\",quotaRequests.memory=\"$quotaRequestsMem\"
    if [[ $vpa_enabled == 1 ]]; then
        helm install $workflow_name-vpa --namespace workerpools workflow_charts/$workflow_name/vpa --values workflow_charts/$workflow_name/vpa/values.yaml --set updateMode=$vpa_option
    fi

    echo "Waiting for Hyperflow resources to be running..."
    kubectl wait --for=condition=Ready --all-namespaces --all pod --timeout=1h
    kubectl wait --for=condition=complete -n workerpools job/nfs-data --timeout=1h

    if [[ $vpa_enabled == 1 ]]; then
        kubectl apply -n workerpools -f workflow_charts/$workflow_name/prometheus_rules.yaml

        echo "Waiting for Prometheus rules to be updated..."
        sleep 30 # Sleeping to make sure the rules are populated to Prometheus
    fi

    echo "Created Hyperflow"
}

run_workflow() {
    engine_pod_name="$(kubectl get pods -n workerpools --no-headers -o custom-columns=":metadata.name" | grep hyperflow-engine)"

    kubectl -n workerpools cp workflow_charts/$workflow_name/workflow.config.executionModels.json $engine_pod_name:/work_dir/workflow.config.executionModels.json

    kubectl -n workerpools exec -it $engine_pod_name -- sh -c 'export RABBIT_HOSTNAME=rabbitmq.default && cd work_dir && hflow run .'
}

fetch_metrics() {
    engine_pod_name="$(kubectl get pods -n workerpools --no-headers -o custom-columns=":metadata.name" | grep hyperflow-engine)"
    
    helm upgrade --install parser charts/parser --values values/cluster/parser.yml -n workerpools
    kubectl wait --for=condition=complete -n workerpools job/logs-parser --timeout=1h

    helm upgrade --install viz-trace charts/viz-trace --values values/cluster/viz-trace.yaml -n workerpools
    kubectl wait --for=condition=complete -n workerpools job/viz-exec-trace --timeout=1h

    parsed_dir_name="$(kubectl exec -it $engine_pod_name -n workerpools -- ls --color=never work_dir/parsed)"
    parsed_dir_name=${parsed_dir_name::${#parsed_dir_name}-1}

    result_dir="cyf_"
    suffix=""
    if [[ $vpa_enabled == 1 ]]; then
        result_dir+="vpa_${vpa_option}_"
        suffix="${vpa_opt}_"
    else
        result_dir+="no_vpa_"
    fi
    result_dir+="${num_nodes}_${machine_type}_${quotaRequestsCpu}_${quotaRequestsMem}_${workerRequestsCpu}cpu_${workerRequestsMem}mem_${suffix}${parsed_dir_name}"

    kubectl -n workerpools cp $engine_pod_name:/work_dir/parsed/$parsed_dir_name $result_dir --retries 5

    if [[ $vpa_enabled == 1 ]]; then
        kubectl get vpa -n workerpools > $result_dir/vpa.txt
    fi
}

if [[ $create_gke_cluster == 1 ]]; then # c
    create_cluster
    connect_cluster

    if [[ $custom_disk == 1 ]]; then
        create_custom_disk
    fi
fi

if [[ $purge_workflow_data == 1 ]]; then # p
    purge_data
fi

if [[ $build_hyperflow_cluster == 1 ]]; then # b
    build_hyperflow
fi

if [[ $run_hyperflow_workflow == 1 ]]; then # s
    run_workflow
fi

if [[ $fetch_metrics_img == 1 ]]; then # f
    fetch_metrics
fi

if [[ $delete_gke_cluster == 1 ]]; then # d
    delete_cluster

    if [[ $custom_disk == 1 ]]; then
        delete_custom_disk
    fi
fi


# helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
# helm repo update
# helm upgrade --install --set args={--kubelet-insecure-tls} metrics-server metrics-server/metrics-server --namespace kube-system
