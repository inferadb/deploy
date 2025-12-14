# AWS Auto Scaling Group with Mixed Instances Policy
# Combines spot and on-demand instances for high availability with cost optimization

resource "aws_autoscaling_group" "workers_mixed" {
  count = var.provider_type == "aws" && var.use_spot_instances ? 1 : 0

  name                = "${var.cluster_name}-workers-mixed"
  desired_capacity    = var.worker_count
  min_size            = 1
  max_size            = var.worker_count * 2
  vpc_zone_identifier = var.subnet_ids

  # Mixed instances policy for spot + on-demand
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 1 # Always keep 1 on-demand
      on_demand_percentage_above_base_capacity = 0 # Rest are spot
      spot_allocation_strategy                 = "capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.worker_spot[0].id
        version            = "$Latest"
      }

      # Diversify instance types for better spot availability
      # Use multiple instance types to reduce interruption risk
      override {
        instance_type     = "t3.xlarge"
        weighted_capacity = 1
      }
      override {
        instance_type     = "t3a.xlarge"
        weighted_capacity = 1
      }
      override {
        instance_type     = "t2.xlarge"
        weighted_capacity = 1
      }
    }
  }

  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete              = true
  termination_policies      = ["OldestInstance"]

  # Tags
  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Cluster"
    value               = var.cluster_name
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "MixedInstances"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# CloudWatch metric alarm for high interruption rate
resource "aws_cloudwatch_metric_alarm" "spot_interruption_rate" {
  count = var.provider_type == "aws" && var.use_spot_instances ? 1 : 0

  alarm_name          = "${var.cluster_name}-spot-interruption-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SpotInstanceInterruptions"
  namespace           = "AWS/EC2Spot"
  period              = 300
  statistic           = "Sum"
  threshold           = 2
  alarm_description   = "Alert when spot instance interruption rate is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.workers_mixed[0].name
  }
}

# Auto Scaling Policy - Scale up
resource "aws_autoscaling_policy" "scale_up" {
  count = var.provider_type == "aws" && var.use_spot_instances ? 1 : 0

  name                   = "${var.cluster_name}-workers-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.workers_mixed[0].name
}

# Auto Scaling Policy - Scale down
resource "aws_autoscaling_policy" "scale_down" {
  count = var.provider_type == "aws" && var.use_spot_instances ? 1 : 0

  name                   = "${var.cluster_name}-workers-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.workers_mixed[0].name
}
