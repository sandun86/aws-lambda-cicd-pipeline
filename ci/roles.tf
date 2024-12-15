# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_role" {
  for_each = var.lambda_functions

  name               = format("%.64s", upper("${local.name_prefix}-${each.key}"))
  assume_role_policy = data.aws_iam_policy_document.lambdas.json

  tags = {
    Name = "Lambda Execution Role"
  }
}

# Common IAM Assume Role Policy
data "aws_iam_policy_document" "lambdas" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Create IAM Policy Documents dynamically
data "aws_iam_policy_document" "lambda_policy" {
  for_each = var.lambda_functions

  dynamic "statement" {
    for_each = local.lambda_policies[each.key]

    content {
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

# IAM Policies for Lambda Functions
resource "aws_iam_policy" "lambda_policy" {
  for_each = var.lambda_functions

  policy = data.aws_iam_policy_document.lambda_policy[each.key].json
}

# IAM Policy Attachments for Lambda Functions
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  for_each = var.lambda_functions

  policy_arn = aws_iam_policy.lambda_policy[each.key].arn
  role       = aws_iam_role.lambda_role[each.key].name
}

# IAM basic execution role policy attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  for_each = var.lambda_functions

  role       = aws_iam_role.lambda_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}