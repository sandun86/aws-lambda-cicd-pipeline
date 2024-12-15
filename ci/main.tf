provider "aws" {
  region = var.aws_region
}

#tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "tf_bucket" {
  bucket = "tf-${var.environment}-bucket-117"
}

resource "aws_s3_bucket_ownership_controls" "tf_bucket" {
  bucket = aws_s3_bucket.tf_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "tf_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.tf_bucket]

  bucket = aws_s3_bucket.tf_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "tf_bucket" {
  bucket = aws_s3_bucket.tf_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "versioning_tf_bucket" {
  bucket = aws_s3_bucket.tf_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "mykey" {
  description             = "This key is used to encrypt"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_bucket" {
  bucket = aws_s3_bucket.tf_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.mykey.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Define paths and methods in locals
locals {
  name_prefix = var.environment
  account_id  = var.account_id
  base_paths = {
    user_login                   = "user/login"
    user_me                      = "user/me"
  }

  lambda_methods = {
    "user-login"                                 = { method = "POST", path = "${var.aws_region}/${local.base_paths.user_unity_login}", gateway_path = local.base_paths.user_unity_login, requires_auth = false }
    "user-me"                                    = { method = "GET", path = "${var.aws_region}/${local.base_paths.user_unity_me}", gateway_path = local.base_paths.user_unity_me, requires_auth = true }
  }

  resource_ids = {
    "user-login"                                 = aws_api_gateway_resource.user_login_resource.id
    "user-me"                                    = aws_api_gateway_resource.user_me_resource.id
  }

  lambda_policies = {
    user-login = [
      {
        effect  = "Allow"
        actions = ["ssm:GetParameter"]
        resources = [
          "arn:aws:ssm:${var.aws_region}:${var.account_id}:*"
        ]
      }
    ]
    user-me = [
      {
        effect  = "Allow"
        actions = ["ssm:GetParameter"]
        resources = [
          "arn:aws:ssm:${var.aws_region}:${var.account_id}:*"
        ]
      }
    ]
  }
}

# Resource to create the ZIP files before deploying the Lambda functions
# resource "null_resource" "zip_lambdas" {
#   for_each = var.lambda_functions

#   provisioner "local-exec" {
#     command = "zip -r ${each.value.directory}/function.zip ${each.value.directory} -x '*.git*' '*node_modules*'"
#   }

#   triggers = {
#     source_hash = filemd5("${path.module}/${each.value.directory}/function.zip")
#   }
# }

# Lambda Functions
resource "aws_lambda_function" "lambda" {
  for_each = var.lambda_functions

  function_name = each.key
  role          = aws_iam_role.lambda_role[each.key].arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  filename      = "${path.module}/${each.value.directory}/function.zip"
  memory_size   = each.value.memory_size
  timeout       = each.value.timeout

  source_code_hash = filebase64sha256("${path.module}/${each.value.directory}/function.zip")

  environment {
    variables = {
      environment = var.environment
    }
  }

  tags = {
    Name = each.key
  }

  depends_on = [aws_iam_role.lambda_role, aws_iam_role_policy_attachment.lambda_basic_execution]
}


