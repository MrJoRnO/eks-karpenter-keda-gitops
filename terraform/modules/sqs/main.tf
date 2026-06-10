# Application queue — job pods receive and delete messages from here
resource "aws_sqs_queue" "messages" {
  name                       = var.queue_name
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400  # 1 day
  receive_wait_time_seconds  = 20     # long polling saves cost

  tags = var.tags
}

# Interruption queue — Karpenter uses this to handle Spot interruption notices
# and rebalance recommendations from EventBridge before the instance is reclaimed.
resource "aws_sqs_queue" "interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300  # 5 min is plenty for spot interruption events
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid     = "AllowEventBridge"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
    resources = [aws_sqs_queue.interruption.arn]
  }
}

# EventBridge rules that forward Spot interruption notices to the queue
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.cluster_name}-spot-interruption"
  description = "Karpenter: Spot instance interruption warning"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "karpenter-interruption"
  arn       = aws_sqs_queue.interruption.arn
}
