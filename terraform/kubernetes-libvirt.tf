# Networking
variable "domain" { default = "kube.local" }
variable "prefix_ip" { default = "192.168.115"}

# OS base image
variable "base_image_path" { default = "../packer/output/ubuntu_kube.qcow2"}

# Master Node
variable "master_hostname" { default = "ubuntu-master" }
variable "master_memory_mb" { default = 2 * 1024 }
variable "master_cpu" { default = 2 }
variable "master_disk_size_gb" { default = 8 }
variable "master_octet_ip" { default = 5}

# Worker Node
variable "number_workers" { default = 4 }
variable "worker_hostname" { default = "ubuntu-worker" }
variable "worker_memory_mb" { default = 2 * 1024 }
variable "worker_cpu" { default = 2 }
variable "worker_disk_size_gb" { default = 8 }
variable "worker_octet_ip" { default = 10}

# SSH
variable "ssh_user" { default = "ubuntu"}
variable "ssh_public_key" { default= "./.ssh/id_rsa.pub" }
variable "ssh_private_key" { default = "./.ssh/id_rsa"}


##################

# Virtualization provider
provider "libvirt" {
  uri = "qemu:///system"
}

# OS image to use as base
resource "libvirt_volume" "os_base" {
  name = "ubuntu-base"
  pool = "default"
  source = var.base_image_path
  format = "qcow2"
}

######### Master ###########

# OS volume
resource "libvirt_volume" "os_image_master" {
  base_volume_id = libvirt_volume.os_base.id
  base_volume_pool = "default"
  name = "${var.master_hostname}-os_image"
  pool = "default"
  format = "qcow2"
  size = var.master_disk_size_gb * 1024 * 1024 * 1024 # Value must be in bytes, https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/volume.html.markdown
}

# External configuration files for CloudInit
data "template_file" "user_data_master" {
  template = file("${path.module}/cloud-init/master/user-data.cfg")
  vars = {
    fqdn = "${var.master_hostname}.${var.domain}"
    ssh_public_key = file(var.ssh_public_key)
  }
}

data "template_file" "network_config_master" {
  template = file("${path.module}/cloud-init/master/network-config.cfg")
  vars = {
    prefix_ip = var.prefix_ip
    octet_ip = var.master_octet_ip
    domain = var.domain
  }
}

resource "libvirt_cloudinit_disk" "master" {
  name = "${var.master_hostname}-cloud_init.iso"
  pool = "default"
  user_data = data.template_file.user_data_master.rendered # We use .rendered because we read the file
  network_config = data.template_file.network_config_master.rendered
}


# Create the Master VM
resource "libvirt_domain" "VM_master" {

  name   = var.master_hostname
  memory = var.master_memory_mb
  vcpu   = var.master_cpu

  qemu_agent = true

  network_interface {
    network_name = "kube"
  }

  disk {
    volume_id = libvirt_volume.os_image_master.id
  }

  cloudinit = libvirt_cloudinit_disk.master.id

  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = true
  }

  ## Ansible playbook.
  # First, we need to wait for cloud-init to finish
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = "${var.prefix_ip}.${var.master_octet_ip}"
    private_key = file(var.ssh_private_key)
    }
  }

  # Then, we execute ansible with an inline inventory
  provisioner "local-exec" {
    command = "ansible-playbook -i '${var.prefix_ip}.${var.master_octet_ip},' --private-key ${var.ssh_private_key} ${path.module}/ansible/master/playbook.yaml"
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = false,
      NODE_IP = "${var.prefix_ip}.${var.master_octet_ip}"
    }
  }
}


######### Workers ##########

# Image to use for the worker nodes
resource "libvirt_volume" "os_image_worker" {
  count = var.number_workers
  base_volume_id = libvirt_volume.os_base.id
  base_volume_pool = "default"
  name = "${var.worker_hostname}-${count.index+1}-os_image"
  pool = "default"
  format = "qcow2"
  size = var.worker_disk_size_gb * 1024 * 1024 * 1024 # Value must be in bytes, https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/volume.html.markdown
}

# External configuration files
data "template_file" "user_data_worker" {
  count = var.number_workers
  template = file("${path.module}/cloud-init/worker/user-data.cfg")
  vars = {
    fqdn = "${var.worker_hostname}-${count.index+1}.${var.domain}"
    ssh_public_key = file(var.ssh_public_key)
  }
}

data "template_file" "network_config_worker" {
  count  = var.number_workers
  template = file("${path.module}/cloud-init/worker/network-config.cfg")
  vars = {
    prefix_ip = var.prefix_ip
    octet_ip = var.worker_octet_ip+count.index+1
    domain = var.domain
  }
}

# Run CloudInit inside the new machine
resource "libvirt_cloudinit_disk" "worker" {
  count  = var.number_workers
  name = "${var.worker_hostname}-${count.index+1}-cloud_init.iso"
  pool = "default"
  user_data = data.template_file.user_data_worker[count.index].rendered # We use .rendered because we read the file
  network_config = data.template_file.network_config_worker[count.index].rendered
}


# Create the Workers VMs
resource "libvirt_domain" "VM_worker" {
  count  = var.number_workers
  
  # Don't create the workers until the master is ready
  depends_on = [libvirt_domain.VM_master]

  name   = "${var.worker_hostname}-${count.index+1}"
  memory = var.worker_memory_mb
  vcpu   = var.worker_cpu

  qemu_agent = true

  network_interface {
    network_name = "kube"
  }

  disk {
    volume_id = libvirt_volume.os_image_worker[count.index].id
  }

  cloudinit = libvirt_cloudinit_disk.worker[count.index].id

  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = true
  }

  ## Ansible playbook.
  # First, we need to wait for cloud-init to finish
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = "${var.prefix_ip}.${var.worker_octet_ip+count.index+1}"
    private_key = file(var.ssh_private_key)
    }
  }

  # Then, we execute ansible with an inline inventory
  provisioner "local-exec" {
    command = "ansible-playbook -i '${var.prefix_ip}.${var.worker_octet_ip+count.index+1},' --private-key ${var.ssh_private_key} ${path.module}/ansible/worker/playbook.yaml"
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = false,
      NODE_IP = "${var.prefix_ip}.${var.worker_octet_ip+count.index+1}"
    }
  }
}