output "queue_arn"               { value = aws_sqs_queue.messages.arn }
output "queue_url"               { value = aws_sqs_queue.messages.url }
output "queue_name"              { value = aws_sqs_queue.messages.name }
output "interruption_queue_name" { value = aws_sqs_queue.interruption.name }
output "interruption_queue_arn"  { value = aws_sqs_queue.interruption.arn }
