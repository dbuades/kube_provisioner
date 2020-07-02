# Networking
domain = "kube.local"
prefix_ip = "192.168.115"

# OS base image
base_image_path = "../packer/output/ubuntu_kube.qcow2"

# Master Node
master_hostname = "ubuntu-master"
master_memory_mb = 4 * 1024
master_cpu = 2
master_disk_size_gb = 8
master_octet_ip = 5

# Worker Node
number_workers = 4
worker_hostname = "ubuntu-worker"
worker_memory_mb = 6 * 1024
worker_cpu = 4
worker_disk_size_gb = 8
worker_octet_ip = 10

# SSH
ssh_user = "ubuntu"
ssh_public_key = "./.ssh/id_rsa.pub"
ssh_private_key = "./.ssh/id_rsa"