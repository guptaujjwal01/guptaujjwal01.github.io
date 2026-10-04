# Uploads the site to the S3 bucket behind CloudFront and clears CloudFront's cache.
# Needs the AWS CLI signed in (aws configure / aws sso login) and site.yaml deployed as the stack "clarv-site".
#   powershell -ExecutionPolicy Bypass -File aws\deploy.ps1
$ErrorActionPreference = "Stop"
$region = "ap-southeast-2"; $stack = "clarv-site"   # the project's one region (aws/README.md)
$env:Path = "C:\Program Files\Amazon\AWSCLIV2;$env:Path"
$root = Split-Path -Parent $PSScriptRoot

function Out($key) {
  aws cloudformation describe-stacks --region $region --stack-name $stack `
    --query "Stacks[0].Outputs[?OutputKey=='$key'].OutputValue" --output text
}
$bucket = Out "BucketName"; $dist = Out "DistributionId"
if (-not $bucket -or $bucket -eq "None") { throw "Stack $stack has no BucketName output - deploy aws\site.yaml first." }

# Pages are re-checked on every visit (a fix shows at once); the stylesheet and logo may be kept a day.
aws s3 sync $root "s3://$bucket" --region $region --delete --exclude "*" --include "*.html" `
  --cache-control "public, max-age=0, must-revalidate" --content-type "text/html; charset=utf-8"
if ($LASTEXITCODE) { throw "upload of the pages failed" }
aws s3 sync $root "s3://$bucket" --region $region --delete --exclude "*" --include "*.css" --include "*.svg" `
  --cache-control "public, max-age=86400"
if ($LASTEXITCODE) { throw "upload of the assets failed" }

aws cloudfront create-invalidation --distribution-id $dist --paths "/*" --query "Invalidation.Id" --output text
if ($LASTEXITCODE) { throw "the cache clear failed" }
Write-Host "Uploaded to s3://$bucket; CloudFront $dist is refreshing (a minute or two)."
