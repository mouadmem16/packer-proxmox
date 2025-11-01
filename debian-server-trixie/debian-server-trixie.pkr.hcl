# Debian Server Trixie (13.1.x)
# ---
# Packer Template to create an Debian Trixie (Trixie 13.1.x) on Proxmox

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
source "proxmox-iso" "debian-server-trixie" {

    # Proxmox Connection Settings
    proxmox_url = "${var.proxmox_api_url}"
    username    = "${var.proxmox_api_token_id}"
    token       = "${var.proxmox_api_token_secret}"
    # (Optional) Skip TLS Verification
    insecure_skip_tls_verify = true

    # VM General Settings
    node                 = "proxmox"
    vm_id                = "402"
    vm_name              = "debian-server-trixie"
    template_description = "Debian Server Trixie Image"

    # VM OS Settings
    # (Option 1) Local ISO File
    boot_iso {
        type         = "scsi"
        iso_file     = "workload:iso/debian-13.1.0-amd64-netinst.iso"
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
        "c<wait>",
        "linux /install.amd/vmlinuz auto-install/enable=true priority=critical ",
        "DEBIAN_FRONTEND=text preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg noprompt<enter>",
        "initrd /install.amd/initrd.gz<enter>",
        "boot<enter>"
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

    name    = "debian-server-trixie"
    sources = ["source.proxmox-iso.debian-server-trixie"]

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

    # Add additional provisioning scripts here
    # ...
}
