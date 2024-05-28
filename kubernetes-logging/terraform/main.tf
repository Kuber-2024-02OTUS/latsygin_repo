terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = var.token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

// Создание сети и подсетей
resource "yandex_vpc_network" "log_net" {
  name          = "logging-network"
  description   = "Logging network created with module"
}

resource "yandex_vpc_subnet" "log_subnet_1" {
  v4_cidr_blocks = ["10.10.0.0/24"]
  zone           = "ru-central1-a"
  network_id     = "${yandex_vpc_network.log_net.id}"
}

// Создание security group с необходимыми правилами
resource "yandex_vpc_security_group" "log_sec_group" {
  name        = "Logging security group"
  description = "Logging security group description"
  network_id  = "${yandex_vpc_network.log_net.id}"

  ingress {
    protocol          = "TCP"
    description       = "Network balancer traffic"
    from_port         = 0
    to_port           = 65535
    predefined_target = "loadbalancer_healthchecks"
  }

  ingress {
    protocol          = "ANY"
    description       = "Service traffic between master and workers"
    from_port         = 0
    to_port           = 65535
    predefined_target = "self_security_group"
  }

  ingress {
    protocol          = "ANY"
    description       = "To transfer traffic between pods and services"
    v4_cidr_blocks    = ["10.10.0.0/24"]
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    protocol          = "ICMP"
    description       = "To check the health of nodes using ICMP requests from subnets inside Yandex Cloud"
    v4_cidr_blocks    = ["10.10.0.0/24"]
  }

  ingress {
    protocol          = "TCP"
    description       = "A rule for connecting to services from the Internet"
    v4_cidr_blocks    = ["0.0.0.0/0"]
    from_port         = 30000
    to_port           = 32767
  }

  ingress {
    protocol          = "TCP"
    description       = "A rule for connecting to hosts via SSH"
    v4_cidr_blocks    = ["176.214.49.206/32"]
    port              = 22
  }

// !!! ВАЖНО: необходимо указать свою сеть из которой будет осуществляться доступ к кластеру иначе не достучаться
  ingress {
    protocol          = "TCP"
    description       = "Rules for accessing the Kubernetes API"
    v4_cidr_blocks    = ["176.214.189.67/32"]
    port              = 443
  }

  ingress {
    protocol          = "TCP"
    description       = "Rules for accessing the Kubernetes API"
    v4_cidr_blocks    = ["176.214.49.206/32"]
    port              = 6443
  }

  egress {
    protocol       = "ANY"
    description    = "A rule for outgoing traffic that allows cluster hosts to connect to external resources"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

}

data "yandex_resourcemanager_folder" "log_folder" {
  name     = "default"
  cloud_id = "b1gd7ecpduahvv28ljmk"
}

resource "yandex_logging_group" "log_group" {
  name      = "k8s-logging-group"
  folder_id = "${data.yandex_resourcemanager_folder.log_folder.id}"
}

#-------------------------------------- Создание s3 бакета
// Создание сервисного аккаунта для доступа к s3 бакету
resource "yandex_iam_service_account" "bucket_sa" {
  name        = "sa-k8s-bucket-tf"
  description = "service account for access s3"
}

// Создание статических ключей доступа
resource "yandex_iam_service_account_static_access_key" "sa-s3-static-key" {
  service_account_id = yandex_iam_service_account.bucket_sa.id
  description        = "static access key for s3 object storage"
}

// Предоставление роли storage.admin на каталог для сервисного аккаунта
resource "yandex_resourcemanager_folder_iam_member" "sa-s3-admin"  {
  folder_id          = "${data.yandex_resourcemanager_folder.log_folder.id}"
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.bucket_sa.id}"
}

// Создание бакетов и одновременно раздача грантов
resource "yandex_storage_bucket" "loki-logs-chunks" {
  access_key = yandex_iam_service_account_static_access_key.sa-s3-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-s3-static-key.secret_key
  bucket = "tf-loki-logs-bucket-chunks"
  # Чтобы управлять параметром grant, у сервисного аккаунта, на который получены статические ключи доступа, должна быть роль storage.admin на бакет или каталог.
  grant {
    id          = "${yandex_iam_service_account.bucket_sa.id}"
    type        = "CanonicalUser"
    permissions = ["FULL_CONTROL"]
  }
}
resource "yandex_storage_bucket" "loki-logs-ruler" {
  access_key = yandex_iam_service_account_static_access_key.sa-s3-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-s3-static-key.secret_key
  bucket = "tf-loki-logs-bucket-ruler"
  grant {
    id          = "${yandex_iam_service_account.bucket_sa.id}"
    type        = "CanonicalUser"
    permissions = ["FULL_CONTROL"]
  }
}
resource "yandex_storage_bucket" "loki-logs-admin" {
  access_key = yandex_iam_service_account_static_access_key.sa-s3-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-s3-static-key.secret_key
  bucket = "tf-loki-logs-bucket-admin"
  grant {
    id          = "${yandex_iam_service_account.bucket_sa.id}"
    type        = "CanonicalUser"
    permissions = ["FULL_CONTROL"]
  }
}

#--------------------------------------
// Create ServiceAccount for manage cluster
resource "yandex_iam_service_account" "log_sa" {
  name        = "sa-k8s-log-tf"
  description = "service account to manage VMs"
}

resource "yandex_resourcemanager_folder_iam_binding" "registry_account_iam" {
#   service_account_id = "${yandex_iam_service_account.log_sa.id}"
  folder_id          = "${data.yandex_resourcemanager_folder.log_folder.id}"
  role               = "container-registry.images.puller"

  members = [
    "serviceAccount:${yandex_iam_service_account.log_sa.id}",
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "k8s_account_agent" {
#   service_account_id = "${yandex_iam_service_account.log_sa.id}"
  folder_id          = "${data.yandex_resourcemanager_folder.log_folder.id}"
  role               = "k8s.clusters.agent"

  members = [
    "serviceAccount:${yandex_iam_service_account.log_sa.id}",
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "vpc_public_admin" {
#   service_account_id = "${yandex_iam_service_account.log_sa.id}"
  folder_id          = "${data.yandex_resourcemanager_folder.log_folder.id}"
  role               = "vpc.publicAdmin"

  members = [
    "serviceAccount:${yandex_iam_service_account.log_sa.id}",
  ]
}

resource "yandex_kubernetes_cluster" "tf_k8s_zonal" {
  name        = "tf-k8s"
  description = "My cluster"

  network_id = "${yandex_vpc_network.log_net.id}"

  master {
    version = "1.28"
    zonal {
        zone      = "${yandex_vpc_subnet.log_subnet_1.zone}"
        subnet_id = "${yandex_vpc_subnet.log_subnet_1.id}"
    }

    public_ip = true

    security_group_ids = ["${yandex_vpc_security_group.log_sec_group.id}"]

    maintenance_policy {
      auto_upgrade = true

      maintenance_window {
        start_time = "15:00"
        duration   = "3h"
      }
    }

  }

  service_account_id      = "${yandex_iam_service_account.log_sa.id}"
  node_service_account_id = "${yandex_iam_service_account.log_sa.id}"

  network_policy_provider = "CALICO"
}

resource "yandex_kubernetes_node_group" "work_load_node" {
  cluster_id  = yandex_kubernetes_cluster.tf_k8s_zonal.id
  name        = "work-load-node"
  description = "Work load group"
  version     = var.k8s_version

  node_labels = {
    "node-role" = "work"
  }

  instance_template {
    name = "work-{instance.index}"
    platform_id = var.platform_id

    network_interface {
      nat                = true
      subnet_ids         = ["${yandex_vpc_subnet.log_subnet_1.id}"]
    }

    resources {
      memory = var.memory
      cores  = var.cores
    }

    boot_disk {
      type = var.disk_type
      size = var.disk_size
    }

    container_runtime {
      type = "containerd"
    }

    metadata = {
      ssh-keys = "vvndtt:${file(var.public_key_path)}"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }
}

resource "yandex_kubernetes_node_group" "infra_node_group" {
  cluster_id  = "${yandex_kubernetes_cluster.tf_k8s_zonal.id}"
  name        = "infra-node-group"
  description = "Infra service group"
  version     = var.k8s_version

  node_labels = {
    "node-role" = "infra"
  }

  node_taints = ["node-role=infra:NoSchedule"]

  instance_template {
    name = "infra-{instance.index}"
    platform_id = var.platform_id

    network_interface {
      nat                = true
      subnet_ids         = ["${yandex_vpc_subnet.log_subnet_1.id}"]
    }

    resources {
      memory = var.memory
      cores  = var.cores
    }

    boot_disk {
      type = var.disk_type
      size = var.disk_size
    }

    scheduling_policy {
      preemptible = false
    }

    container_runtime {
      type = "containerd"
    }

    metadata = {
      ssh-keys = "vvndtt:${file(var.public_key_path)}"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }

  provisioner "local-exec" {
    command = "yc managed-kubernetes cluster get-credentials $CLUSTER_NAME --external --force --folder-id $FOLDER_ID"
    environment = {
      CLUSTER_NAME = var.cluster_name
      FOLDER_ID    = var.folder_id
    }
  }
}

output "access_key" {
    value = yandex_iam_service_account_static_access_key.sa-s3-static-key.access_key
}
output "secret_key" {
    value = yandex_iam_service_account_static_access_key.sa-s3-static-key.secret_key
    sensitive = true
}
