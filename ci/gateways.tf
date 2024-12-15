resource "aws_lambda_function" "authorizer" {
  function_name    = "authenticate-token"
  filename         = "${path.module}/../apis/authenticate-token/function.zip"
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = filebase64sha256("${path.module}/../apis/authenticate-token/function.zip")
  role             = aws_iam_role.lambda_exec_role.arn

  memory_size = 512
  timeout     = 15

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = format("%.64s", upper("${var.environment}-Authenticate-lambda_exec_role"))
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

# Inline policy to access Secrets Manager
resource "aws_iam_policy" "secrets_manager_access" {
  name = format("%.64s", upper("${var.environment}-Authenticate-SecretsManagerAccess-${random_string.suffix.result}"))

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${var.account_id}:*"
        ]
      }
    ]
  })
}

# Attach the Secrets Manager inline policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "secrets_manager_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.secrets_manager_access.arn
}

resource "aws_lambda_permission" "authorizer_invoke" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer-${var.environment}-${aws_lambda_function.authorizer.function_name}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda_api.execution_arn}/authorizers/*"
}


resource "aws_api_gateway_authorizer" "lambda_authorizer" {
  name            = "unity-authenticate-token-1"
  rest_api_id     = aws_api_gateway_rest_api.lambda_api.id
  authorizer_uri  = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.authorizer.arn}/invocations"
  type            = "REQUEST"
  identity_source = "method.request.header.token,method.request.header.email"

  authorizer_result_ttl_in_seconds = 0 # Set to 0 to disable caching

  depends_on = [
    aws_lambda_permission.authorizer_invoke
  ]
}

# Create API Gateway REST API
resource "aws_api_gateway_rest_api" "lambda_api" {
  name        = "lambda-apis"
  description = "API Gateway for lambda APIs"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Create the /user resource
resource "aws_api_gateway_resource" "user_resource" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id   = aws_api_gateway_rest_api.lambda_api.root_resource_id
  path_part   = "user"
}

# Create the /user/login resource, nested under /user
resource "aws_api_gateway_resource" "user_login_resource" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id   = aws_api_gateway_resource.user_resource.id 
  path_part   = "login"
}

resource "aws_api_gateway_resource" "user_me_resource" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id   = aws_api_gateway_resource.user_resource.id 
  path_part   = "me"
}

resource "aws_api_gateway_method" "lambda_method" {
  for_each = local.lambda_methods

  rest_api_id   = aws_api_gateway_rest_api.lambda_api.id
  resource_id   = local.resource_ids[each.key] # Use the resource ID map
  http_method   = each.value.method
  authorization = each.value.requires_auth ? "CUSTOM" : "NONE"
  authorizer_id = each.value.requires_auth ? aws_api_gateway_authorizer.lambda_authorizer.id : null
}


resource "aws_api_gateway_integration" "lambda_integration" {
  for_each = local.lambda_methods

  rest_api_id             = aws_api_gateway_rest_api.lambda_api.id
  resource_id             = aws_api_gateway_method.lambda_method[each.key].resource_id
  http_method             = aws_api_gateway_method.lambda_method[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda["${each.key}"].invoke_arn
}

resource "aws_api_gateway_method_response" "api_response" {
  for_each = local.lambda_methods

  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  resource_id = local.resource_ids[each.key]
  http_method = aws_api_gateway_method.lambda_method[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "api_integration_response" {
  for_each = local.lambda_methods

  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  resource_id = local.resource_ids[each.key]
  http_method = aws_api_gateway_method.lambda_method[each.key].http_method
  status_code = aws_api_gateway_method_response.api_response[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "lambda_deployment" {
  depends_on = [
    aws_api_gateway_integration_response.api_integration_response,
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method_response.api_response,
    aws_api_gateway_method.lambda_method
  ]

  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  stage_name  = var.stage

  triggers = {
    redeployment = timestamp()
  }

  description = "Deployment - ${timestamp()}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "lambda_permission" {
  for_each = local.lambda_methods

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda_api.execution_arn}/*/${each.value.method}/${each.value.gateway_path}"
}


