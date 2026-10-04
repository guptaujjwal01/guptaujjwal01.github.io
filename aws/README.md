# clarv.in on AWS

The site moves from GitHub Pages to a private S3 bucket behind CloudFront, with its certificate from ACM and the
domain's DNS on Route 53. Nothing goes down on the way: the Route 53 zone first copies what Squarespace serves today
(the GitHub Pages records and the iCloud+ mail records), the nameservers are switched, and only then are the site
records pointed at CloudFront.

Written and linted (cfn-lint clean) on 4 Oct 2026; NOT yet run — no AWS account, CLI or credentials on this PC.

## What it costs

Route 53 zone US$0.50 a month plus queries; S3 and CloudFront for a site this size stay within cents (CloudFront's
always-free tier is 1 TB and 10 million requests a month); the certificate is free.

## Steps

Every command runs from this folder's parent (`C:\Users\gupta\projects\clarv-site`), region `us-east-1` throughout
(CloudFront certificates must be issued there; Route 53 is global).

1. **AWS account and CLI** — the same account as the Clarv application. Install the CLI
   (`winget install Amazon.AWSCLI`) and sign in yourself (`aws configure` with an IAM user's keys, or `aws sso login`).

2. **The zone** (a copy of today's DNS, still pointing at GitHub Pages):

   ```
   aws cloudformation deploy --region us-east-1 --stack-name clarv-zone --template-file aws/zone.yaml
   aws cloudformation describe-stacks --region us-east-1 --stack-name clarv-zone --query "Stacks[0].Outputs"
   ```

   Before switching, compare the zone with the live one: `Resolve-DnsName clarv.in -Type MX -Server <one of the
   four NameServers>` should answer the two iCloud servers, and `-Type TXT` the SPF and `apple-domain` lines. If
   iCloud's Custom Email Domain page shows a DKIM value other than `sig1.dkim.clarv.in.at.icloudmailadmin.com`, change
   the `Dkim` record first.

3. **Nameservers** — at Squarespace: Domains › clarv.in › DNS › Nameservers › use custom nameservers, enter the four
   from the `NameServers` output. Propagation takes minutes to a day; the site and mail keep working throughout,
   because both zones say the same thing.

4. **The site stack** (once `Resolve-DnsName clarv.in -Type NS` answers the awsdns servers):

   ```
   aws cloudformation deploy --region us-east-1 --stack-name clarv-site --template-file aws/site.yaml --parameter-overrides HostedZoneId=<HostedZoneId>
   ```

   It waits while ACM validates the certificate through the zone (a few minutes) and CloudFront deploys (up to 15).

5. **Upload**: `powershell -ExecutionPolicy Bypass -File aws\deploy.ps1`. Check it before the switch on the
   distribution's own address: `https://<DistributionDomain>/` (the browser warns about the name; the page itself
   should load).

6. **Switch the site to CloudFront**:

   ```
   aws cloudformation deploy --region us-east-1 --stack-name clarv-zone --template-file aws/zone.yaml --parameter-overrides SiteTarget=cloudfront CloudFrontDomain=<DistributionDomain>
   ```

   When the Clarv application's stack is up, add `AppIp=<its PublicIp>` to the same command; that writes
   `app.clarv.in`, which replaces the registrar step in the application's DEPLOY.md.

7. **Retire GitHub Pages** once `https://clarv.in` answers from CloudFront (`Invoke-WebRequest https://clarv.in -Method
   Head` shows `Via: … cloudfront`): the repository's Settings › Pages › Unpublish. Keep the repo — it stays the
   source; every later change is `git commit` then `aws\deploy.ps1`.

## What it sets

- The bucket is private, encrypted, versioned and kept if the stack is deleted; only this distribution can read it.
- HTTPS only (TLS 1.2 or later), HTTP/2 and HTTP/3, IPv6, AWS's managed security headers (HSTS, nosniff,
  frame-options, referrer policy).
- `www.clarv.in` answers 301 to `https://clarv.in` with the same path.
- Pages are re-checked on every visit, the stylesheet and logo kept a day; every upload clears CloudFront's cache.
