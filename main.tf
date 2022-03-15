# -------------------------------------------------------
# TECHNOGIX
# -------------------------------------------------------
# Copyright (c) [2021] Technogix.io
# All rights reserved
# -------------------------------------------------------
# Module to deploy an aws instance with all the secure
# components required
# -------------------------------------------------------
# Nadège LEMPERIERE, @18 january 2021
# Latest revision: 18 january 2021
# -------------------------------------------------------

# -------------------------------------------------------
# Matching os with associated ami
# -------------------------------------------------------
locals {
    images = {
        eu-west-1 = [
            { os = "Ubuntu-20.04", ami = "ami-08ca3fed11864d6bb", owner = "099720109477" },
            { os = "Ubuntu-18.04", ami = "ami-07d8796a2b0f8d29c", owner = "099720109477" },
            { os = "Ubuntu-16.04", ami = "ami-0f29c8402f8cce65c", owner = "099720109477" },
            { os = "Suze-15sp3", ami = "ami-02be7a0d5d4276ce2", owner = "013907871322" },
            { os = "RedHat-8", ami = "ami-0ec23856b3bad62d3", owner = "309956199498" },
            { os = "Debian-10", ami = "ami-0874dad5025ca362c", owner = "136693071363"},
            { os = "Suze-12sp5", ami = "ami-05f4fa0bf79b2856e", owner = "013907871322" },
            { os = "Amazon-5.10", ami = "ami-01efa4023f0f3a042", owner = "099720109477" },
            { os = "Amazon-4.14", ami = "ami-096f7a9ab885b50f4", owner = "099720109477" },
            { os = "Microsoft-2019", ami = "ami-0765c672acf861672", owner = "801119661308"},
            { os = "Microsoft-2022", ami = "ami-05e400f66139c3ff6", owner = "801119661308"},
            { os = "Microsoft-2016", ami = "ami-04d14fd4d6c2e3a0e", owner = "801119661308"}
        ]
    }


    region_images      = lookup(local.images, var.region)
    points_map         = { for i, ept in local.region_images : tostring(i) => ept }
    images_map         = compact([for i, ept in local.region_images : ept.os == var.os ? i : ""])
    selected_images = [for key in local.images_map : lookup(local.points_map, key)]
    image              = local.selected_images[0].ami
    owner            = local.selected_images[0].owner
}

# -------------------------------------------------------
# Load an official aws image
# -------------------------------------------------------
data    "aws_ami"     "instance" {

    owners             = [local.owner]

    filter {
        name         = "image-id"
        values         = [local.image]
    }

    tags = {
        Name                   = "${var.project}.${var.environment}.${var.module}.instance.${var.name}"
        Environment         = var.environment
        Owner               = var.email
        Project               = var.project
        Version             = var.git_version
        Module              = var.module
    }

}

# -------------------------------------------------------
# Create instance
# -------------------------------------------------------
locals {
    subnets = [ for i, sub in var.networks : {index = i}]
}
resource "aws_instance" "instance" {

    depends_on         = [aws_network_interface.subnet]

    ami                = data.aws_ami.instance.id
    instance_type      = var.size

    monitoring         = true
    hibernation        = false

    dynamic "network_interface" {
        for_each = local.subnets
        content {
            device_index             = network_interface.value.index
            network_interface_id     = aws_network_interface.subnet[network_interface.value.index].id
        }
    }

    root_block_device {
        encrypted     = true
        kms_key_id     = aws_kms_key.key.arn
        volume_size    = var.disk.size
        volume_type    = var.disk.type

        tags = {
            Name                = "${var.project}.${var.environment}.${var.module}.instance.${var.name}"
            Environment         = var.environment
            Owner               = var.email
            Project             = var.project
            Version             = var.git_version
            Module              = var.module
        }
    }

    tags = {
        Name                = "${var.project}.${var.environment}.${var.module}.instance.${var.name}"
        Environment         = var.environment
        Owner               = var.email
        Project             = var.project
        Version             = var.git_version
        Module              = var.module
    }
}

# -------------------------------------------------------
# Create a network interface for each network
# -------------------------------------------------------
resource "aws_network_interface" "subnet" {

    count                = length(var.networks)
    subnet_id            = var.networks[count.index].subnet
      security_groups    = [aws_security_group.subnet[count.index].id]

    tags = {
        Name            = "${var.project}.${var.environment}.${var.module}.instance.${var.name}.subnet${count.index}.interface"
        Environment     = var.environment
        Owner           = var.email
        Project         = var.project
        Version         = var.git_version
        Module          = var.module
    }
}

# -------------------------------------------------------
# Create a security group for instance network interface
# -------------------------------------------------------
resource "aws_security_group" "subnet" {

    count         = length(var.networks)

    name          = "${var.project}-instance-${var.name}-subnet${count.index}"
      vpc_id      = var.vpc

      tags = {
        Name            = "${var.project}.${var.environment}.${var.module}.instance.${var.name}.subnet${count.index}.nsg"
        Environment     = var.environment
        Owner           = var.email
        Project         = var.project
        Version         = var.git_version
        Module          = var.module
    }
}

# -------------------------------------------------------
# Add rules in nsg to enable instance access to resources
# -------------------------------------------------------
locals {
    egress  = flatten([ for i, sub in var.networks : [ for j, rule in sub.egress : merge(rule,{index = i, sg = aws_security_group.subnet[i].id})]])
    ingress = flatten([ for i, sub in var.networks : [ for j, rule in sub.ingress : merge(rule,{index = i, sg = aws_security_group.subnet[i].id})]])
}
resource "aws_security_group_rule" "egress" {

    count = length(local.egress)

    depends_on                   = [aws_security_group.subnet]
    description                  = local.egress[count.index].description
    security_group_id            = local.egress[count.index].sg
    type                         = "egress"
    protocol                     = local.egress[count.index].protocol
    cidr_blocks                  = ["${local.egress[count.index].cidr}"]
    ipv6_cidr_blocks             = []
    prefix_list_ids              = []
    from_port                    = local.egress[count.index].from
    to_port                      = local.egress[count.index].to
}
resource "aws_security_group_rule" "ingress" {

    count = length(local.ingress)

    depends_on                   = [aws_security_group.subnet]
    description                  = local.ingress[count.index].description
    security_group_id            = local.ingress[count.index].sg
    type                         = "ingress"
    protocol                     = local.ingress[count.index].protocol
    cidr_blocks                  = ["${local.ingress[count.index].cidr}"]
    ipv6_cidr_blocks             = []
    prefix_list_ids              = []
    from_port                    = local.ingress[count.index].from
    to_port                      = local.ingress[count.index].to
}

# -------------------------------------------------------
# Formatting data for output
# -------------------------------------------------------
resource "null_resource" "interfaces" {

    count = length(var.networks)

    triggers = {
        group = aws_security_group.subnet[count.index].id
        subnet = var.networks[count.index].subnet
        interface = aws_network_interface.subnet[count.index].id
        device = count.index
        dns = aws_network_interface.subnet[count.index].private_dns_name
    }
}

# -------------------------------------------------------
# Instance disk encryption key
# -------------------------------------------------------
resource "aws_kms_key" "key" {

    description                 = "EC2 Instance encryption key"
    key_usage                   = "ENCRYPT_DECRYPT"
    customer_master_key_spec    = "SYMMETRIC_DEFAULT"
    deletion_window_in_days     = 7
    enable_key_rotation         = true
    policy                      = jsonencode({
          Version = "2012-10-17",
          Statement = [
            {
                Sid             = "AllowKeyModificationToRootAndGod"
                Effect          = "Allow"
                Principal       = {
                    "AWS" : [
                        "arn:aws:iam::${var.account}:root",
                        "arn:aws:iam::${var.account}:user/${var.service_principal}"
                    ]
                }
                Action          = [ "kms:*" ],
                Resource        = "*"
               }
          ]
    })

    tags = {
        Name            = "${var.project}.${var.environment}.${var.module}.instance.${var.name}"
        Environment     = var.environment
        Owner           = var.email
        Project         = var.project
        Version         = var.git_version
        Module          = var.module
    }
}
