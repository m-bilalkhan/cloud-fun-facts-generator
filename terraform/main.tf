data "aws_caller_identity" "current" {}

#----------------------------
# IAM - Creating policy for Lambda role
#----------------------------
data "aws_iam_policy_document" "this" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

#----------------------------
# IAM - Assuming role for Lambda execution
#----------------------------
resource "aws_iam_role" "this" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.this.json
}

#----------------------------
# IAM - Attach required managed policy - Basic Lambda Execution
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#----------------------------
# IAM - Attach required managed policy - DynamoDB ReadOnly Access
#----------------------------
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

#----------------------------
# IAM - Attach required managed policy - Amazon Bedrock Full Access
#----------------------------
resource "aws_iam_role_policy_attachment" "bedrock_access" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

#----------------------------
# Packing the Lambda function code
#----------------------------
data "archive_file" "this" {
  type        = "zip"
  source_file = "../lambda/lambda_function.py"
  output_path = "${path.module}/lambda/function.zip"
}

#----------------------------
# Lambda - Function
#----------------------------
resource "aws_lambda_function" "funfacts_generator" {
  filename         = data.archive_file.this.output_path
  function_name    = "CloudFunFacts"
  role             = aws_iam_role.this.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.this.output_base64sha256
  publish          = true
  timeout          = 20

  runtime = "python3.13"

  tags = {
    Application = "Fun Facts Generator"
  }
}

#----------------------------
# Lambda - API Gateway Invoke Permission
#----------------------------
resource "aws_lambda_permission" "allow_apigw" {
  depends_on    = [aws_apigatewayv2_api.this]
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.funfacts_generator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:ap-south-1:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.this.id}/*"

}

#----------------------------
# API Gateway - API Creation
#----------------------------
resource "aws_apigatewayv2_api" "this" {
  name          = "FunfactsAPI"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["Content-Type","Authorization","X-Amz-Date","X-Api-Key","X-Amz-Security-Token"]
    allow_methods = ["GET","OPTIONS"]
    allow_origins = ["*"]
    expose_headers = ["*"]
    max_age       = 3600
  }
}

#----------------------------
# API Gateway - Lambda Integration
#----------------------------
resource "aws_apigatewayv2_integration" "this" {
  depends_on       = [aws_lambda_function.funfacts_generator]
  api_id           = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"

  description          = "Lambda Function"
  integration_method   = "POST"
  integration_uri      = aws_lambda_function.funfacts_generator.arn
  passthrough_behavior = "WHEN_NO_MATCH"
}

#----------------------------
# API Gateway - Writing Route
#----------------------------
resource "aws_apigatewayv2_route" "this" {
  depends_on = [aws_lambda_function.funfacts_generator]
  api_id     = aws_apigatewayv2_api.this.id
  route_key  = "GET /"

  target = "integrations/${aws_apigatewayv2_integration.this.id}"
}

#----------------------------
# API Gateway - Staging
#----------------------------
resource "aws_apigatewayv2_stage" "example" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

#----------------------------
# Dynamodb - Facts Storage Table
#----------------------------
resource "aws_dynamodb_table" "basic-dynamodb-table" {
  name           = "CloudFacts"
  hash_key       = "FactID"
  range_key      = "FactText"
  read_capacity  = 10
  write_capacity = 10

  attribute {
    name = "FactID"
    type = "S"
  }

  attribute {
    name = "FactText"
    type = "S"
  }

  tags = {
    Name = "CloudFacts"
  }
}

#----------------------------
# Locals
#----------------------------
locals {
  json_data = file("./data.json")
  tf_data   = jsondecode(local.json_data)
}

#----------------------------
# Provisioning initial data into DynamoDB
#----------------------------
resource "aws_dynamodb_table_item" "initial_data" {
  for_each   = local.tf_data
  table_name = aws_dynamodb_table.basic-dynamodb-table.name
  hash_key   = "FactID"
  range_key  = "FactText"
  item       = jsonencode(each.value)
}

output "api_invoke_url" {
  value = aws_apigatewayv2_api.this.api_endpoint
}