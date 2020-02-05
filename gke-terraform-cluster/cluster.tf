resource "google_service_account" "service_account" {
  account_id   = "my-service-account"
  display_name = "Service Account"
}

resource "google_project_iam_binding" "admin-account-gke-iam" {
  role               = "roles/container.admin"

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]
}

resource "google_project_iam_binding" "admin-account-storage-iam" {
  role               = "roles/storage.admin"

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]
}

resource "google_service_account_key" "mykey" {
  service_account_id = google_service_account.service_account.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

provider "google" {
  project     = var.gcp_project_id
}

resource "google_project_service" "kubernetes" {
  project = var.gcp_project_id
  service = "container.googleapis.com"
  disable_dependent_services = true
}

resource "google_container_cluster" "primary" {
  name        = var.gcp_cluster_name
  depends_on  = ["google_project_service.kubernetes"]
  location    = var.gcp_zone

  initial_node_count = 6

  node_config {
    machine_type = "e2-small"
  }
}

resource "google_project_service" "compute_engine" {
  project = var.gcp_project_id
  service = "compute.googleapis.com"
  disable_dependent_services = true
}



provider "kubernetes" {
  version = "1.10.0-custom"
  host = "${google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = "${base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)}"
}

resource "kubernetes_secret" "google-application-credentials" {
  metadata {
    name = "google-application-credentials"
  }
  data = {
    credentials = "${base64decode(google_service_account_key.mykey.private_key)}"
  }
}

resource "kubernetes_cluster_role_binding" "serviceaccounts_cluster_admin" {
  metadata {
    name = "serviceaccounts-cluster-admin"
  }

  subject {
    kind = "Group"
    name = "system:serviceaccounts"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
}

resource "kubernetes_service" "nfs_server" {
  metadata {
    name = "nfs-server"
  }

  spec {
    port {
      name = "nfs"
      port = 2049
    }

    port {
      name = "mountd"
      port = 20048
    }

    port {
      name = "rpcbind"
      port = 111
    }

    selector = {
      role = "nfs-server"
    }
  }
}

resource "kubernetes_persistent_volume" "nfs" {
  metadata {
    name = "nfs"
  }

  spec {
    capacity = {
      storage = "1Gi"
    }

    access_modes = ["ReadWriteMany"]

    persistent_volume_source {
      nfs {
        path   = "/"
        server = "nfs-server.default.svc.cluster.local"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "nfs" {
  metadata {
    name = "nfs"
  }

  spec {
    access_modes = ["ReadWriteMany"]

    storage_class_name = ""

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
