variable "aws_region" {
  description = "The AWS region where Lambda functions will be deployed"
  default     = "eu-north-1"
}

variable "environment" {
  description = "The deployment environment"
  default     = "dev"
}

variable "project_name" {
  description = "lambda apis"
  default     = "lambda"
}

variable "account_id" {
  description = "AWS account id"
  default     = "381491972792"
}

variable "stage" {
  description = "stage name"
  default     = "v1"
}

variable "s3_bucket_name" {
  description = "s3 bucket"
  default     = "v1"
}

variable "lambda_functions" {
  type = map(object({
    filename    = string
    directory   = string
    memory_size = number
    timeout     = number
  }))
  default = {
    login = {
      filename    = "../apis/login/function.zip"
      directory   = "../apis/login"
      memory_size = 256
      timeout     = 30
    }
    me = {
      filename    = "../apis/me/function.zip"
      directory   = "../apis/me"
      memory_size = 256
      timeout     = 30
    }
  }
}

variable "create_authorizer" {
  description = "Set to true to create the Lambda Authorizer, or false to skip it."
  type        = bool
  default     = true # You can set this to false if you don't want the authorizer by default
}

