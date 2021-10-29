/**************************************************/
/* Terraform script for creating rekognition custom face collection - services, API, web UI

	Terraform Version: 0.11
	Output: API URL, CLOUDFRONT UI URL, S3 TRAINING BUCKET
	TJ Feneran - tffenera@amazon.com

/* SET VARIABLES(REGION, ACCOUNT ID, THRESHOLDS), AND ACCESS/SECRET KEYS BELOW: */
/**************************************************/

// Set AWS Region in which to deploy this workload. 
variable "region" {
	type = "string"
	default = "us-east-1" 
}

// You can uncomment & set access_key and secret_key below if not present in environment variables. Not recommended to hard-code. 
provider "aws" {
	access_key = "********" 		
	secret_key = "************"  
	region     = "${var.region}" // set region above, not here.
}

/**************************************************/
/* DO NOT CHANGE ANYTHING BELOW THIS LINE */
/**************************************************/

// GENERATE RANDOM STR
resource "random_string" "bucket_random" {
  length = 16,
  special = false,
  upper = false,
  number = false
}

data "aws_caller_identity" "current" {}

// CREATE API
resource "aws_api_gateway_rest_api" "RekogAPI" {
	name        = "Rekog-API-${random_string.bucket_random.result}"
	description = "REST API for Custom Collection Web UI"
	endpoint_configuration {
		types = ["REGIONAL"]
	}
	binary_media_types = ["multipart/form-data"]
	body = "${data.template_file.api-tpl.rendered}"
}

data "template_file" "api-tpl" {
	template = "${file("assets/API Gateway JSON/openapi3.json")}"
	vars = {
	    region = "${var.region}",
	    accountid = "${data.aws_caller_identity.current.account_id}"
	}
}

// DEPLOY API
resource "aws_api_gateway_deployment" "apigw_deployment_prod" {
  rest_api_id = "${aws_api_gateway_rest_api.RekogAPI.id}"
  stage_name = "Production"
}

// CREATE TWO S3 BUCKETS	
resource "aws_s3_bucket" "bucket-ui" {
	bucket = "rekog-ui-${random_string.bucket_random.result}"
	website {
		index_document = "index.html"
		error_document = "error.html"
	}	
	tags = {
		Name = "s3-rekog-ui"
	}
}

resource "aws_s3_bucket" "bucket-src" {
	bucket = "rekog-src-${random_string.bucket_random.result}"
	tags = {
		Name = "s3-rekog-src"
	}
}

//OAI
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
	comment = "Rekog OAI"
}

// SET S3 BUCKET POLICIES
resource "aws_s3_bucket_policy" "bucketpolicy-ui" {
	  bucket = "${aws_s3_bucket.bucket-ui.id}"
	  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "Policy1548123778809",
    "Statement": [
        {
            "Sid": "Stmt1548123759484",
            "Effect": "Allow",
            "Principal": {"AWS":"${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"},
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${aws_s3_bucket.bucket-ui.id}/*"
        },
        {
            "Sid": "Stmt1548123777996",
            "Effect": "Allow",
            "Principal": {"AWS":"${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"},
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${aws_s3_bucket.bucket-ui.id}"
        }
    ]
}
POLICY
}

resource "aws_s3_bucket_policy" "bucketpolicy-src" {
	  bucket = "${aws_s3_bucket.bucket-src.id}"
	  policy = <<POLICY
{
  "Id": "Policy1574009846379",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1574009845563",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.bucket-src.id}/*",
      "Principal": {
  		"AWS": [
    		"${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}",
    		"${aws_iam_role.lambda_exec_role.arn}"
    	],
    	"Service": [
    		"rekognition.amazonaws.com"
    	]
      }
    }
  ]
}
POLICY
}

//CLOUDFRONT DISTRO
resource "aws_cloudfront_distribution" "distro_rekog" {
	origin {
		domain_name = "${aws_s3_bucket.bucket-ui.bucket_regional_domain_name}"
		origin_id = "CFS3OriginUI"
		s3_origin_config {
			origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
		}
	}
	origin {
		domain_name = "${aws_s3_bucket.bucket-src.bucket_regional_domain_name}"
		origin_id = "CFS3OriginSrc"
		s3_origin_config {
			origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
		}
	}
	tags = {
		Name = "Rekog POC Distro"
	}

	enabled = true
	is_ipv6_enabled = true
	comment = "CloudFront Distribution for Rekog POC UI on S3"
	default_root_object = "index.html"
	price_class = "PriceClass_100"
	logging_config {
	    include_cookies = false
	    bucket          = "tj-aws.s3.amazonaws.com"
	    prefix          = "cflogs"
	  }
	default_cache_behavior {
	    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
	    cached_methods   = ["GET", "HEAD"]
	    target_origin_id = "CFS3OriginUI"

		forwarded_values {
			query_string = false
			cookies {
				forward = "none"
			}
		}

		viewer_protocol_policy = "redirect-to-https"
		min_ttl                = 0
		default_ttl            = 30 //3600
		max_ttl                = 86400
	}

	ordered_cache_behavior {
	    path_pattern     = "*.jpg"
	    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
	    cached_methods   = ["GET", "HEAD"]
	    target_origin_id = "CFS3OriginSrc"

	    forwarded_values {
	      query_string = false
	      cookies {
	        forward = "none"
	      }
	    }

	    min_ttl                = 0
	    default_ttl            = 30 //86400
	    max_ttl                = 31536000
	    compress               = true
	    viewer_protocol_policy = "redirect-to-https"
    }
    ordered_cache_behavior {
	    path_pattern     = "*.JPG"
	    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
	    cached_methods   = ["GET", "HEAD"]
	    target_origin_id = "CFS3OriginSrc"

	    forwarded_values {
	      query_string = false
	      cookies {
	        forward = "none"
	      }
	    }

	    min_ttl                = 0
	    default_ttl            = 30 //86400
	    max_ttl                = 31536000
	    compress               = true
	    viewer_protocol_policy = "redirect-to-https"
    }
    ordered_cache_behavior {
	    path_pattern     = "*.jpeg"
	    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
	    cached_methods   = ["GET", "HEAD"]
	    target_origin_id = "CFS3OriginSrc"

	    forwarded_values {
	      query_string = false
	      cookies {
	        forward = "none"
	      }
	    }

	    min_ttl                = 0
	    default_ttl            = 30 //86400
	    max_ttl                = 31536000
	    compress               = true
	    viewer_protocol_policy = "redirect-to-https"
    }
	ordered_cache_behavior {
	    path_pattern     = "*.png"
	    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
	    cached_methods   = ["GET", "HEAD"]
	    target_origin_id = "CFS3OriginSrc"

	    forwarded_values {
	      query_string = false
	      cookies {
	        forward = "none"
	      }
	    }

	    min_ttl                = 0
	    default_ttl            = 30 //86400
	    max_ttl                = 31536000
	    compress               = true
	    viewer_protocol_policy = "redirect-to-https"
    }
	ordered_cache_behavior {
	    path_pattern     = "*.PNG"
	    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
	    cached_methods   = ["GET", "HEAD"]
	    target_origin_id = "CFS3OriginSrc"

	    forwarded_values {
	      query_string = false
	      cookies {
	        forward = "none"
	      }
	    }

	    min_ttl                = 0
	    default_ttl            = 30 //86400
	    max_ttl                = 31536000
	    compress               = true
	    viewer_protocol_policy = "redirect-to-https"
    }

    viewer_certificate {
		cloudfront_default_certificate = true
	}
	restrictions {
		geo_restriction {
			restriction_type = "whitelist"
			locations = ["US", "CA"]
		}
	}
}

// OUTPUTS
output "Open this UI URL > " {
	value = "${aws_cloudfront_distribution.distro_rekog.domain_name}"
}
output "S3Bucket > Source" {
  value = "${aws_s3_bucket.bucket-src.id}"
}
output "API URL >" {
  value = "https://${aws_api_gateway_deployment.apigw_deployment_prod.rest_api_id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_deployment.apigw_deployment_prod.stage_name}"
}

// COPY UI FILES TO UI BUCKET
data "template_file" "ui-app-js" {
  template = "${file("assets/UI/app.tpl")}"
  vars = {
    api_url = "https://${aws_api_gateway_deployment.apigw_deployment_prod.rest_api_id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_deployment.apigw_deployment_prod.stage_name}",
    cf_distro = "${aws_cloudfront_distribution.distro_rekog.domain_name}",
    ui_url = "${aws_s3_bucket.bucket-ui.website_endpoint}",
    s3sourcebucket = "${aws_s3_bucket.bucket-src.id}",
    region = "${var.region}"
  }
}

resource "aws_s3_bucket_object" "ui-html" {
	bucket = "${aws_s3_bucket.bucket-ui.id}"
	key = "index.html"
	source = "assets/UI/index.html"
	content_type = "text/html"
	etag   = "${md5(file("assets/UI/index.html"))}"
}
resource "aws_s3_bucket_object" "ui-css" {
	bucket = "${aws_s3_bucket.bucket-ui.id}"
	key = "app.css"
	source = "assets/UI/app.css"
	content_type = "text/css"
	etag   = "${md5(file("assets/UI/app.css"))}"
}
resource "aws_s3_bucket_object" "ui-js" {
	bucket = "${aws_s3_bucket.bucket-ui.id}"
	key = "app.js"
	content = "${data.template_file.ui-app-js.rendered}"
	content_type = "text/javascript"
	etag   = "${md5(file("assets/UI/app.js"))}"
}
resource "aws_s3_bucket_object" "uploader-js" {
	bucket = "${aws_s3_bucket.bucket-ui.id}"
	key = "dm-uploader.js"
	source = "assets/UI/dm-uploader.js"
	content_type = "text/html"
	etag   = "${md5(file("assets/UI/dm-uploader.js"))}"
}

// SET INGEST TRIGGER
resource "aws_s3_bucket_notification" "SrcPut" {
	bucket = "${aws_s3_bucket.bucket-src.id}"
	lambda_function {
		lambda_function_arn = "${aws_lambda_function.lambda-s3ingest.arn}"
		events              = ["s3:ObjectCreated:*"]
	}
}

// CREATE MAIN DYNAMODB TABLE
resource "aws_dynamodb_table" "ddbtable" {
	name = "rekog-namedb-${random_string.bucket_random.result}"
	billing_mode = "PROVISIONED"
	read_capacity = 15
	write_capacity = 5
	hash_key = "faceid"
	
	attribute {
		name = "faceid"
		type = "S"
	}
	tags = {
		Name = "rekog-namedb"
	}
}

// CREATE LAMBDA EXECUTION ROLE
resource "aws_iam_role" "lambda_exec_role" {
	name = "lambda_exec_role_${random_string.bucket_random.result}"
	assume_role_policy = <<EOF
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Action": "sts:AssumeRole",
			"Principal": {
				"Service": "lambda.amazonaws.com"
			}
		}
	]
}
EOF
}
// CREATE POLICY FOR ABOVE ROLE
resource "aws_iam_role_policy" "Lambda-Exec-Policy" {
	name = "Lambda-Exec-Policy"
	role = "${aws_iam_role.lambda_exec_role.id}"
	policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:*",
				"rekognition:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
            	"s3:ListBucket",
            	"s3:GetObject",
            	"s3:DeleteObject",
            	"s3:PutObject"
            ],
            "Resource": [
				"${aws_s3_bucket.bucket-src.arn}",
				"${aws_s3_bucket.bucket-src.arn}/*"
			]
        },
		{
			"Effect": "Allow",
            "Action": [
                "dynamodb:DeleteItem",
				"dynamodb:PutItem",
				"dynamodb:UpdateItem",
				"dynamodb:GetItem",
				"dynamodb:Query",
				"dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:*"
		}
    ]
}
EOF
}

// CREATE LAMBDA S3 INVOCATION PERMISSION [needed to allow event trigger to a bucket]
resource "aws_lambda_permission" "allow_bucket-src" {
	statement_id  = "AllowExecutionFromS3Bucket"
	action        = "lambda:InvokeFunction"
	function_name = "${aws_lambda_function.lambda-s3ingest.arn}"
	principal     = "s3.amazonaws.com"
	source_arn    = "${aws_s3_bucket.bucket-src.arn}"
	source_account = "${data.aws_caller_identity.current.account_id}"
}

// CREATE LAMBDA LAYER VERSION - REQUEST LIBRARY FOR URL REQUESTS
resource "aws_lambda_layer_version" "lambda_layer_request" {
	filename = "assets/Lambda Layers/RequestLayer.zip"
	layer_name = "RequestLayer"
	compatible_runtimes = ["nodejs10.x"]
	description = "Request library for http/s calls"
}
// CREATE LAMBDA LAYER VERSION - UI IMAGE UPLOAD BACKEND UTILITY
resource "aws_lambda_layer_version" "lambda_layer_parsemultipart" {
	filename = "assets/Lambda Layers/ParseMultipartLayer.zip"
	layer_name = "ParseMultipartLayer"
	compatible_runtimes = ["nodejs10.x"]
	description = "Parses multipart/form-data event.body"
}

// CREATE LAMBDA FUNCTIONS


// Upload Image
resource "aws_lambda_function" "lambda-uploadimage" {
	function_name = "rekog-uploadimage"
	handler = "uploadimage.handler"
	runtime = "nodejs10.x"
	filename = "assets/Lambda Functions/uploadimage.js.zip"
	source_code_hash = "${base64sha256(file("assets/Lambda Functions/uploadimage.js.zip"))}"
	role = "${aws_iam_role.lambda_exec_role.arn}"
	timeout = 10,
	memory_size = 192,
	layers = ["${aws_lambda_layer_version.lambda_layer_parsemultipart.arn}"]
	environment = {
		variables = {
			REGION = "${var.region}"
			SOURCEBUCKET = "${aws_s3_bucket.bucket-src.id}"
		}
	}
}
//permit apigw to call above lambda fn
resource "aws_lambda_permission" "lambda_permission_uploadimage" {
	statement_id  = "AllowAPIInvoke"
	action        = "lambda:InvokeFunction"
	function_name = "${aws_lambda_function.lambda-uploadimage.function_name}"
	principal     = "apigateway.amazonaws.com"
	source_arn	  = "${aws_api_gateway_rest_api.RekogAPI.execution_arn}/*/*/*"
}

//Delete Collections
resource "aws_lambda_function" "lambda-deletecollections" {
	function_name = "rekog-deletecollections"
	handler = "deletecollections.handler"
	runtime = "nodejs10.x"
	filename = "assets/Lambda Functions/deletecollections.js.zip"
	source_code_hash = "${base64sha256(file("assets/Lambda Functions/deletecollections.js.zip"))}"
	role = "${aws_iam_role.lambda_exec_role.arn}"
	timeout = 20
	environment = {
		variables = {
			REGION = "${var.region}"
			DYNAMODBTABLE = "${aws_dynamodb_table.ddbtable.id}"
			SOURCEBUCKET = "${aws_s3_bucket.bucket-src.id}"
		}
	}
}
//permit apigw to call above lambda fn
resource "aws_lambda_permission" "lambda_permission_deletecollections" {
	statement_id  = "AllowAPIInvoke"
	action        = "lambda:InvokeFunction"
	function_name = "${aws_lambda_function.lambda-deletecollections.function_name}"
	principal     = "apigateway.amazonaws.com"
	source_arn	  = "${aws_api_gateway_rest_api.RekogAPI.execution_arn}/*/*/*"
}

//Delete a Face
resource "aws_lambda_function" "lambda-deletefaces" {
	function_name = "rekog-deletefaces"
	handler = "deletefaces.handler"
	runtime = "nodejs10.x"
	filename = "assets/Lambda Functions/deletefaces.js.zip"
	source_code_hash = "${base64sha256(file("assets/Lambda Functions/deletefaces.js.zip"))}"
	role = "${aws_iam_role.lambda_exec_role.arn}"
	environment = {
		variables = {
			REGION = "${var.region}"
			DYNAMODBTABLE = "${aws_dynamodb_table.ddbtable.id}"
			SRCBUCKET = "${aws_s3_bucket.bucket-src.id}"
		}
	}	
}
//permit apigw to call above lambda fn
resource "aws_lambda_permission" "lambda_permission_deletefaces" {
	statement_id  = "AllowAPIInvoke"
	action        = "lambda:InvokeFunction"
	function_name = "${aws_lambda_function.lambda-deletefaces.function_name}"
	principal     = "apigateway.amazonaws.com"
	source_arn	  = "${aws_api_gateway_rest_api.RekogAPI.execution_arn}/*/*/*"
}

//List Faces
resource "aws_lambda_function" "lambda-listfaces" {
	function_name = "rekog-listfaces"
	handler = "listfaces.handler"
	runtime = "nodejs10.x"
	filename = "assets/Lambda Functions/listfaces.js.zip"
	source_code_hash = "${base64sha256(file("assets/Lambda Functions/listfaces.js.zip"))}"
	role = "${aws_iam_role.lambda_exec_role.arn}"
	environment = {
		variables = {
			REGION = "${var.region}"
			DYNAMODBTABLE = "${aws_dynamodb_table.ddbtable.id}"
		}
	}	
}
//permit apigw to call above lambda fn
resource "aws_lambda_permission" "lambda_permission_listfaces" {
	statement_id  = "AllowAPIInvoke"
	action        = "lambda:InvokeFunction"
	function_name = "${aws_lambda_function.lambda-listfaces.function_name}"
	principal     = "apigateway.amazonaws.com"
	source_arn	  = "${aws_api_gateway_rest_api.RekogAPI.execution_arn}/*/*/*"
}

//Training Image Ingest
resource "aws_lambda_function" "lambda-s3ingest" {
	function_name = "rekog-training"
	handler = "s3ingest.handler"
	runtime = "nodejs10.x"
	filename = "assets/Lambda Functions/s3ingest.js.zip"
	source_code_hash = "${base64sha256(file("assets/Lambda Functions/s3ingest.js.zip"))}"
	role = "${aws_iam_role.lambda_exec_role.arn}"
	timeout = 10
	environment = {
		variables = {
			REGION = "${var.region}"
			DYNAMODBTABLE = "${aws_dynamodb_table.ddbtable.id}"
		}
	}
}

//Set a Name
resource "aws_lambda_function" "lambda-setname" {
	function_name = "rekog-setname"
	handler = "setname.handler"
	runtime = "nodejs10.x"
	filename = "assets/Lambda Functions/setname.js.zip"
	source_code_hash = "${base64sha256(file("assets/Lambda Functions/setname.js.zip"))}"
	role = "${aws_iam_role.lambda_exec_role.arn}"
	environment = {
		variables = {
			REGION = "${var.region}"
			DYNAMODBTABLE = "${aws_dynamodb_table.ddbtable.id}"
		}
	}	
}
//permit apigw to call above lambda fn
resource "aws_lambda_permission" "lambda_permission_setname" {
	statement_id  = "AllowAPIInvoke"
	action        = "lambda:InvokeFunction"
	function_name = "${aws_lambda_function.lambda-setname.function_name}"
	principal     = "apigateway.amazonaws.com"
	source_arn	  = "${aws_api_gateway_rest_api.RekogAPI.execution_arn}/*/*/*"
}

