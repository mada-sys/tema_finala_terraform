variable "vm_count" {
  default = 2
}

variable "vm_size" {
  default = "Standard_B1s"
}

variable "vm_image" {
  default = "22_04-lts"
}

variable "admin_password" {
  description = "Parola pentru utilizatorul admin"
  type        = string
  sensitive   = true
}

locals {
  prefix         = "mada"
  admin_username = "mada"
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg13" { # Modificat de la rg12 la rg13
  name     = "${local.prefix}-rg13" # Modificat de la rg12 la rg13
  location = "West Europe"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg13.location # Modificat de la rg12 la rg13
  resource_group_name = azurerm_resource_group.rg13.name     # Modificat de la rg12 la rg13
}

resource "azurerm_subnet" "subnet" {
  name                 = "${local.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg13.name # Modificat de la rg12 la rg13
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${local.prefix}-nsg"
  location            = azurerm_resource_group.rg13.location # Modificat de la rg12 la rg13
  resource_group_name = azurerm_resource_group.rg13.name     # Modificat de la rg12 la rg13

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowICMP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "main" {
  count               = 1
  name                = "${local.prefix}-publicip-0"
  location            = azurerm_resource_group.rg13.location # Modificat de la rg12 la rg13
  resource_group_name = azurerm_resource_group.rg13.name     # Modificat de la rg12 la rg13
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "main" {
  count               = var.vm_count
  name                = "${local.prefix}-nic-${count.index}"
  location            = azurerm_resource_group.rg13.location # Modificat de la rg12 la rg13
  resource_group_name = azurerm_resource_group.rg13.name     # Modificat de la rg12 la rg13

  ip_configuration {
    name                          = "ipconfig-${count.index}"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = count.index == 0 ? azurerm_public_ip.main[0].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  count                     = var.vm_count
  network_interface_id      = azurerm_network_interface.main[count.index].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "main" {
  count                       = var.vm_count
  name                        = "${local.prefix}-vm-${count.index}"
  resource_group_name         = azurerm_resource_group.rg13.name     # Modificat de la rg12 la rg13
  location                    = azurerm_resource_group.rg13.location # Modificat de la rg12 la rg13
  size                        = var.vm_size
  admin_username              = local.admin_username
  admin_password              = var.admin_password
  disable_password_authentication = false
  network_interface_ids       = [azurerm_network_interface.main[count.index].id]

  os_disk {
    name                 = "disk-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22_04-lts"
    version   = "22.04.20250720"
  }
}

locals {
  vm2_private_ip = azurerm_network_interface.main[1].private_ip_address
}

resource "null_resource" "ping_between_vms" {
  depends_on = [azurerm_linux_virtual_machine.main]

  connection {
    host     = azurerm_public_ip.main[0].ip_address
    user     = local.admin_username
    password = var.admin_password
  }

  provisioner "remote-exec" {
    inline = [
      "ping -c 4 ${local.vm2_private_ip}"
    ]
  }
}

output "public_ip_vm1" {
  value = azurerm_public_ip.main[0].ip_address
}

output "private_ip_vm1" {
  value = azurerm_network_interface.main[0].private_ip_address
}

output "private_ip_vm2" {
  value = azurerm_network_interface.main[1].private_ip_address
}