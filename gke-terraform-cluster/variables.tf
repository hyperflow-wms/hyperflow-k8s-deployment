variable "gcp_project_id" {
    type = string
}

variable "gcp_zone" {
    default = "europe-west4-a"
}

variable "gcp_cluster_name" {
    default = "standard-cluster-2"
}

variable "workflow_worker_image"{
    default = "hyperflowwms/montage-workflow-worker:v1.0.0"
}

variable "workflow_data_image"{
    default = "hyperflowwms/montage-workflow-data:montage0.25-bf0b1b4450c201ee5f549c7f473d2ef0"
}
