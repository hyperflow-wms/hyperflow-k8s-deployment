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
}

resource "google_compute_disk" "default" {
  name  = "hf-storage"
  size  =  "1"
  type  = "pd-ssd"
  zone  = "europe-west2-a"
  physical_block_size_bytes = 4096
}
