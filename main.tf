provider "google" {
  credentials = "${file("/tmp/account.json")}"
  project     = var.gcp_project
}

resource "google_container_cluster" "primary" {
  name     = "standard-cluster-1"
  location = "europe-west2-a"

  initial_node_count = 1

  node_config {
    preemptible  = true # cheaper VMs with no availibility guarantee
    machine_type = "g1-small"
  }

  master_auth {
    username = "root"
    password = "AaDISwficf9b5hfHxbUYln0JySF29Wdn"

    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

output "endpoint" {
  value = "${google_container_cluster.primary.endpoint}"
}

provider "kubernetes" {
    host = "${google_container_cluster.primary.endpoint}"
    username = "root"
    password = "AaDISwficf9b5hfHxbUYln0JySF29Wdn"
    cluster_ca_certificate = "${base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)}"
}

resource "google_compute_disk" "default" {
  name  = "hf-storage"
  size  =  "1"
  type  = "pd-ssd"
  zone  = "europe-west2-a"
  physical_block_size_bytes = 4096
}
