# main.tf - This is where I define my providers

terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc07"
    }
  }
}

provider "proxmox" {
  alias                       = "pve03"
  pm_tls_insecure             = true
  pm_api_url                  = "https://10.13.37.7:8006/api2/json"
  pm_api_token_secret         = var.pve03_token_secret
  pm_api_token_id             = var.pve03_token_id
  pm_minimum_permission_check = false # needed until telmate/proxmox updates to fully support PVE 9.x
}
