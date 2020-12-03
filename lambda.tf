data "aws_iam_policy_document" "assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}

resource "aws_iam_role" "lambda" {
  name               = module.label.id
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = ["${aws_s3_bucket.default.arn}/*"]
  }
}

resource "aws_iam_policy" "lambda" {
  name        = module.label.id
  description = "Allow put logs, use s3 to store email and sent emails with SES"
  policy      = data.aws_iam_policy_document.lambda.json
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

module "artifact" {
  source      = "git::https://github.com/cloudposse/terraform-external-module-artifact.git?ref=tags/0.5.0"
  filename    = var.artifact_filename
  module_name = "terraform-aws-ses-lambda-forwarder"
  module_path = path.module
  url         = var.artifact_url
}

resource "aws_lambda_function" "default" {
  filename         = module.artifact.file
  function_name    = module.label.id
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  source_code_hash = module.artifact.base64sha256
  runtime          = var.lambda_runtime

  environment {
    variables = {
      EMAIL_FROM        = var.relay_email
      EMAIL_BUCKET_NAME = aws_s3_bucket.default.bucket
      EMAIL_BUCKET_PATH = ""
      EMAIL_MAPPING     = jsonencode(var.forward_emails)
    }
  }
}

resource "aws_lambda_alias" "default" {
  name             = "default"
  description      = "Use latest version as default"
  function_name    = aws_lambda_function.default.function_name
  function_version = "$LATEST"
}

resource "aws_lambda_permission" "ses" {
  statement_id   = "AllowExecutionFromSES"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.default.function_name
  principal      = "ses.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}
