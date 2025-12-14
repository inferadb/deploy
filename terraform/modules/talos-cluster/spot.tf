# Spot Instance Configuration for Cost Optimization
# AWS Spot Instances and GCP Preemptible/Spot VMs for stateless workloads

# AWS Spot Instance Launch Template
resource "aws_launch_template" "worker_spot" {
  count = var.provider_type == "aws" && var.use_spot_instances ? 1 : 0

  name_prefix   = "${var.cluster_name}-worker-spot-"
  image_id      = data.aws_ami.talos[0].id
  instance_type = local.machine_type_mappings[var.worker_machine_type]["aws"]

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = var.spot_max_price != "" ? var.spot_max_price : null
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop" # Stop instead of terminate for faster recovery
    }
  }

  # Talos machine config is passed via user_data
  user_data = base64encode(data.talos_machine_configuration.worker.machine_configuration)

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name         = "${var.cluster_name}-worker-spot"
        Role         = "worker"
        SpotInstance = "true"
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# GCP Preemptible/Spot Instance Configuration
resource "google_compute_instance_template" "worker_preemptible" {
  count = var.provider_type == "gcp" && var.use_spot_instances ? 1 : 0

  name_prefix  = "${var.cluster_name}-worker-spot-"
  machine_type = local.machine_type_mappings[var.worker_machine_type]["gcp"]
  region       = var.provider_region

  scheduling {
    preemptible         = true
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    # Use Spot VMs (newer, more capacity than legacy preemptible)
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"
  }

  disk {
    source_image = data.google_compute_image.talos[0].self_link
    auto_delete  = true
    boot         = true
    disk_size_gb = 100
    disk_type    = "pd-ssd"
  }

  network_interface {
    network    = var.vpc_id
    subnetwork = var.subnet_ids[0]
  }

  metadata = {
    user-data = data.talos_machine_configuration.worker.machine_configuration
  }

  labels = merge(
    local.common_tags,
    {
      role          = "worker"
      spot-instance = "true"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# GCP Managed Instance Group for preemptible workers
resource "google_compute_region_instance_group_manager" "worker_preemptible" {
  count = var.provider_type == "gcp" && var.use_spot_instances ? 1 : 0

  name               = "${var.cluster_name}-worker-spot"
  base_instance_name = "${var.cluster_name}-worker-spot"
  region             = var.provider_region
  target_size        = var.worker_count

  version {
    instance_template = google_compute_instance_template.worker_preemptible[0].id
  }

  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 0
    instance_redistribution_type = "PROACTIVE"
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.worker[0].id
    initial_delay_sec = 300
  }
}

# GCP health check for workers
resource "google_compute_health_check" "worker" {
  count = var.provider_type == "gcp" && var.use_spot_instances ? 1 : 0

  name = "${var.cluster_name}-worker"

  tcp_health_check {
    port = 10250 # Kubelet port
  }

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}
