output "lambda_arns" {
  description = "The ARNs of the Lambda functions"
  value       = { for name, lambda in aws_lambda_function.lambda : name => lambda.arn }
}
