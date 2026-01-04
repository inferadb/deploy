# Talos Cluster Module
# Abstract module for provisioning Talos Linux clusters across multiple cloud providers

locals {
  # Machine type mappings across providers
  # AWS: Using Graviton (t4g) for ~20% cost savings over x86 (t3)
  machine_type_mappings = {
    small = {
      aws          = "t4g.medium"
      gcp          = "e2-medium"
      digitalocean = "s-2vcpu-4gb"
    }
    medium = {
      aws          = "t4g.xlarge"
      gcp          = "e2-standard-4"
      digitalocean = "s-4vcpu-8gb"
    }
    large = {
      aws          = "t4g.2xlarge"
      gcp          = "e2-standard-8"
      digitalocean = "s-8vcpu-16gb"
    }
  }

  # Common tags for all resources
  common_tags = merge(
    var.tags,
    {
      Environment  = var.environment
      Cluster      = var.cluster_name
      Region       = var.region
      ManagedBy    = "terraform"
      TalosVersion = var.talos_version
      K8sVersion   = var.kubernetes_version
    }
  )

  # Cluster endpoint - will be set by provider-specific modules
  cluster_endpoint = var.provider_type == "aws" ? (
    length(aws_lb.control_plane) > 0 ? aws_lb.control_plane[0].dns_name : ""
    ) : var.provider_type == "gcp" ? (
    length(google_compute_forwarding_rule.control_plane) > 0 ? google_compute_forwarding_rule.control_plane[0].ip_address : ""
    ) : var.provider_type == "digitalocean" ? (
    length(digitalocean_loadbalancer.control_plane) > 0 ? digitalocean_loadbalancer.control_plane[0].ip : ""
  ) : ""

  # Control plane and worker IPs - provider-specific
  control_plane_ips = var.provider_type == "aws" ? (
    [for i in aws_instance.control_plane : i.private_ip]
    ) : var.provider_type == "gcp" ? (
    [for i in google_compute_instance.control_plane : i.network_interface[0].network_ip]
    ) : var.provider_type == "digitalocean" ? (
    [for i in digitalocean_droplet.control_plane : i.ipv4_address_private]
  ) : []

  worker_ips = var.provider_type == "aws" ? (
    var.use_spot_instances ? [] : [for i in aws_instance.worker : i.private_ip]
    ) : var.provider_type == "gcp" ? (
    [for i in google_compute_instance.worker : i.network_interface[0].network_ip]
    ) : var.provider_type == "digitalocean" ? (
    [for i in digitalocean_droplet.worker : i.ipv4_address_private]
  ) : []
}

# Talos machine configuration generation
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${local.cluster_endpoint}:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${local.cluster_endpoint}:6443"
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

# Generate machine secrets for the cluster
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Talos client configuration
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips
}

# Cluster kubeconfig
data "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = local.cluster_endpoint
  node                 = local.control_plane_ips[0]

  depends_on = [
    talos_machine_bootstrap.this
  ]
}

# Bootstrap the Talos cluster (run once on first control plane node)
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = local.control_plane_ips[0]
  node                 = local.control_plane_ips[0]

  depends_on = [
    aws_instance.control_plane,
    google_compute_instance.control_plane,
    digitalocean_droplet.control_plane
  ]
}

# AWS-specific resources
# Control plane instances
resource "aws_instance" "control_plane" {
  count = var.provider_type == "aws" ? var.control_plane_count : 0

  ami           = data.aws_ami.talos[0].id
  instance_type = local.machine_type_mappings["medium"]["aws"]
  subnet_id     = var.subnet_ids[count.index % length(var.subnet_ids)]

  user_data = base64encode(data.talos_machine_configuration.controlplane.machine_configuration)

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-control-plane-${count.index}"
      Role = "control-plane"
    }
  )

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }
}

# AWS worker instances (on-demand only, spot instances use ASG)
resource "aws_instance" "worker" {
  count = var.provider_type == "aws" && !var.use_spot_instances ? var.worker_count : 0

  ami           = data.aws_ami.talos[0].id
  instance_type = local.machine_type_mappings[var.worker_machine_type]["aws"]
  subnet_id     = var.subnet_ids[count.index % length(var.subnet_ids)]

  user_data = base64encode(data.talos_machine_configuration.worker.machine_configuration)

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-worker-${count.index}"
      Role = "worker"
    }
  )

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    encrypted   = true
  }
}

# AWS Load Balancer for control plane
resource "aws_lb" "control_plane" {
  count = var.provider_type == "aws" ? 1 : 0

  name               = "${var.cluster_name}-control-plane"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-control-plane-lb"
    }
  )
}

# AWS data source for Talos AMI
data "aws_ami" "talos" {
  count = var.provider_type == "aws" ? 1 : 0

  most_recent = true
  owners      = ["540036508848"] # Talos official AWS account

  filter {
    name   = "name"
    values = ["talos-${var.talos_version}-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# GCP-specific resources
# Control plane instances
resource "google_compute_instance" "control_plane" {
  count = var.provider_type == "gcp" ? var.control_plane_count : 0

  name         = "${var.cluster_name}-control-plane-${count.index}"
  machine_type = local.machine_type_mappings["medium"]["gcp"]
  zone         = "${var.provider_region}-${["a", "b", "c"][count.index % 3]}"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.talos[0].self_link
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = var.vpc_id
    subnetwork = var.subnet_ids[count.index % length(var.subnet_ids)]
  }

  metadata = {
    user-data = data.talos_machine_configuration.controlplane.machine_configuration
  }

  labels = merge(
    local.common_tags,
    {
      role = "control-plane"
    }
  )
}

# GCP worker instances
resource "google_compute_instance" "worker" {
  count = var.provider_type == "gcp" && !var.use_spot_instances ? var.worker_count : 0

  name         = "${var.cluster_name}-worker-${count.index}"
  machine_type = local.machine_type_mappings[var.worker_machine_type]["gcp"]
  zone         = "${var.provider_region}-${["a", "b", "c"][count.index % 3]}"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.talos[0].self_link
      size  = 100
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = var.vpc_id
    subnetwork = var.subnet_ids[count.index % length(var.subnet_ids)]
  }

  metadata = {
    user-data = data.talos_machine_configuration.worker.machine_configuration
  }

  labels = merge(
    local.common_tags,
    {
      role = "worker"
    }
  )
}

# GCP Load Balancer for control plane
resource "google_compute_forwarding_rule" "control_plane" {
  count = var.provider_type == "gcp" ? 1 : 0

  name                  = "${var.cluster_name}-control-plane"
  region                = var.provider_region
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.control_plane[0].id
  ports                 = ["6443"]
  network               = var.vpc_id
  subnetwork            = var.subnet_ids[0]
}

resource "google_compute_region_backend_service" "control_plane" {
  count = var.provider_type == "gcp" ? 1 : 0

  name          = "${var.cluster_name}-control-plane"
  region        = var.provider_region
  health_checks = [google_compute_health_check.control_plane[0].id]

  backend {
    group = google_compute_instance_group.control_plane[0].id
  }
}

resource "google_compute_instance_group" "control_plane" {
  count = var.provider_type == "gcp" ? 1 : 0

  name = "${var.cluster_name}-control-plane"
  zone = "${var.provider_region}-a"

  instances = [for i in google_compute_instance.control_plane : i.self_link]

  named_port {
    name = "kubernetes"
    port = "6443"
  }
}

resource "google_compute_health_check" "control_plane" {
  count = var.provider_type == "gcp" ? 1 : 0

  name = "${var.cluster_name}-control-plane"

  https_health_check {
    port         = 6443
    request_path = "/healthz"
  }
}

# GCP data source for Talos image
data "google_compute_image" "talos" {
  count = var.provider_type == "gcp" ? 1 : 0

  family  = "talos-${replace(var.talos_version, ".", "-")}"
  project = "talos-cloud-images"
}

# DigitalOcean-specific resources
# Control plane droplets
resource "digitalocean_droplet" "control_plane" {
  count = var.provider_type == "digitalocean" ? var.control_plane_count : 0

  name     = "${var.cluster_name}-control-plane-${count.index}"
  image    = data.digitalocean_image.talos[0].id
  size     = local.machine_type_mappings["medium"]["digitalocean"]
  region   = var.provider_region
  vpc_uuid = var.vpc_id

  user_data = data.talos_machine_configuration.controlplane.machine_configuration

  tags = [
    var.environment,
    var.cluster_name,
    "control-plane"
  ]
}

# DigitalOcean worker droplets
resource "digitalocean_droplet" "worker" {
  count = var.provider_type == "digitalocean" ? var.worker_count : 0

  name     = "${var.cluster_name}-worker-${count.index}"
  image    = data.digitalocean_image.talos[0].id
  size     = local.machine_type_mappings[var.worker_machine_type]["digitalocean"]
  region   = var.provider_region
  vpc_uuid = var.vpc_id

  user_data = data.talos_machine_configuration.worker.machine_configuration

  tags = [
    var.environment,
    var.cluster_name,
    "worker"
  ]
}

# DigitalOcean Load Balancer for control plane
resource "digitalocean_loadbalancer" "control_plane" {
  count = var.provider_type == "digitalocean" ? 1 : 0

  name     = "${var.cluster_name}-control-plane"
  region   = var.provider_region
  vpc_uuid = var.vpc_id

  forwarding_rule {
    entry_port      = 6443
    entry_protocol  = "tcp"
    target_port     = 6443
    target_protocol = "tcp"
  }

  healthcheck {
    port     = 6443
    protocol = "tcp"
  }

  droplet_ids = [for d in digitalocean_droplet.control_plane : d.id]
}

# DigitalOcean data source for Talos image
data "digitalocean_image" "talos" {
  count = var.provider_type == "digitalocean" ? 1 : 0

  name = "talos-${var.talos_version}"
}
