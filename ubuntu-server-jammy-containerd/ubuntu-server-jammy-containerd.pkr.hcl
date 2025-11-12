# Ubuntu Server Jammy (22.04.x)
# ---
# Packer Template to create an Ubuntu Server (Jammy 24.04.x) + Containerd on Proxmox

# Variable Definitions
variable "proxmox_api_url" {
    type = string
}

variable "proxmox_api_token_id" {
    type = string
}

variable "proxmox_api_token_secret" {
    type      = string
    sensitive = true
}

locals {
    disk_storage = "data"
}

# Resource Definiation for the VM Template
source "proxmox-iso" "ubuntu-server-jammy-containerd" {

    # Proxmox Connection Settings
    proxmox_url = "${var.proxmox_api_url}"
    username    = "${var.proxmox_api_token_id}"
    token       = "${var.proxmox_api_token_secret}"
    # (Optional) Skip TLS Verification
    insecure_skip_tls_verify = true

    # VM General Settings
    node                 = "proxmox"
    vm_id                = "402"
    vm_name              = "ubuntu-server-jammy-containerd"
    template_description = "Ubuntu Server Jammy Image with Containerd"

    # VM OS Settings
    # (Option 1) Local ISO File
    boot_iso {
        type         = "scsi"
        iso_file     = "workload:iso/ubuntu-22.04.5-live-server-amd64.iso"
        unmount      = true
        # iso_checksum = "e240e4b801f7bb68c20d1356b60968ad0c33a41d00d828e74ceb3364a0317be9"
    }
    # (Option 2) Download ISO
    # boot_iso {
    #     type             = "scsi"
    #     iso_url          = "https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
    #     unmount          = true
    #     iso_storage_pool = "local"
    #     iso_checksum     = "file:https://releases.ubuntu.com/jammy/SHA256SUMS"
    # }

    # VM System Settings
    qemu_agent = true

    # VM Hard Disk Settings
    scsi_controller = "virtio-scsi-pci"

    disks {
        disk_size         = "10G"
        format            = "raw"
        storage_pool      = "${local.disk_storage}"
        type              = "virtio"
    }

    # VM CPU Settings
    cores = "4"

    # VM Memory Settings
    memory = "4096"

    # VM Network Settings
    network_adapters {
        model    = "virtio"
        bridge   = "vmbr0"
        firewall = "false"
    }

    # VM Cloud-Init Settings
    cloud_init              = true
    cloud_init_storage_pool = "${local.disk_storage}"

    # PACKER Boot Commands
    boot         = "c"
    boot_wait    = "10s"
    communicator = "ssh"
    boot_command = [
        "<esc><wait>",
        "e<wait>",
        "<down><down><down><end>",
        "<bs><bs><bs><bs><wait>",
        "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
        "<f10><wait>"
    ]
    # Useful for debugging
    # Sometimes lag will require this
    # boot_key_interval = "500ms"


    # PACKER Autoinstall Settings
    http_directory          = "http"

    # (Optional) Bind IP Address and Port
    # http_bind_address       = "0.0.0.0"
    # http_port_min           = 8802
    # http_port_max           = 8802

    ssh_username            = "user"

    # (Option 1) Add your Password here
    # ssh_password        = "password"
    # - or -
    # (Option 2) Add your Private SSH KEY file here
    ssh_private_key_file    = "~/.ssh/id_rsa"

    # Raise the timeout, when installation takes longer
    ssh_timeout             = "30m"
    ssh_pty                 = true
}

# Build Definition to create the VM Template
build {

    name    = "ubuntu-server-jammy-containerd"
    sources = ["source.proxmox-iso.ubuntu-server-jammy-containerd"]

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #1
    provisioner "shell" {
        inline = [
            "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
            "sudo rm /etc/ssh/ssh_host_*",
            "sudo truncate -s 0 /etc/machine-id",
            "sudo apt -y autoremove --purge",
            "sudo apt -y clean",
            "sudo apt -y autoclean",
            "sudo cloud-init clean",
            "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
            "sudo rm -f /etc/netplan/00-installer-config.yaml",
            "sudo sync"
        ]
    }

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #2
    provisioner "file" {
        source      = "files/99-pve.cfg"
        destination = "/tmp/99-pve.cfg"
    }

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #3
    provisioner "shell" {
        inline = [ "sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg" ]
    }

    # Fixing the systemd and installing uidmap #4
    provisioner "shell" {
        inline = [ "sudo fwupdmgr refresh", "sudo systemctl restart fwupd-refresh.service", "sudo apt update", "sudo apt install -y uidmap" ]
    }

    # Enabling CPU, CPUSET, and I/O delegation #5
    provisioner "shell" {
        inline = [ 
            "cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers",
            "sudo mkdir -p /etc/systemd/system/user@.service.d",
            "echo -e \"[Service]\nDelegate=cpu cpuset io memory pids\" | sudo tee /etc/systemd/system/user@.service.d/delegate.conf",
            "sudo systemctl daemon-reload",
            "sudo shutdown -r +1 & disown",
            "exit 0"
        ]
    }

    # This provisioner runs AFTER the reboot and successful reconnect.
    provisioner "shell" {
        inline = [
        "echo 'Provisioning resumed after successful reboot!'"
        ]
    }
    
    # Provisioning the VM Template with Full Nerdctl ( Containerd + RunC + CNI ) Installation #6
    provisioner "shell" {
        inline = [
            "wget https://github.com/containerd/nerdctl/releases/download/v2.2.0/nerdctl-full-2.2.0-linux-amd64.tar.gz",
            "sudo tar Cxzvvf /usr/local nerdctl-full-2.2.0-linux-amd64.tar.gz",
            "containerd-rootless-setuptool.sh install"
        ]
    }
}
