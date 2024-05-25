variable "cloud_id" {
  description = "Cloud"
}
variable "folder_id" {
  description = "Folder"
}
variable "token" {
  description = "Provider token"
}
variable "cluster_name" {
  description = "k8s cluster name"
  default     = "tf-k8s"
}
variable "k8s_version" {
  description = "k8s cluster version"
  default     = "1.28"
}
variable "zone" {
  description = "Zone"
  default = "ru-central1-a"
}
variable "public_key_path" {
  description = "Path to the public key used for ssh access"
}
variable "region_id" {
  default     = "ru-central1"
}
variable "platform_id" {
  description = "платформа для узлов"
  default     = "standard-v1"
}
variable "cores" {
  description = "VM cores"
  default     = 2
}
variable "memory" {
  description = "VM memory"
  default     = 4
}
variable "disk_type" {
  description = "Disk storage classes"
  default     = "network-hdd"
}
variable "disk_size" {
  description = "Disk size"
  default     = 30
}
