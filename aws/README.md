# clarv.in on AWS

The site moves from GitHub Pages to a private S3 bucket behind CloudFront, with its certificate from ACM and the
domain's DNS on Route 53. Nothing goes down on the way: the Route 53 zone first copies what Squarespace serves today
(the GitHub Pages records and the iCloud+ mail records), the nameservers are switched, and only then are the site
records pointed at CloudFront.

## The account, as found on 4 Oct 2026

AWS account `949836655208` is a "project" of the new AWS experience, a member of the organisation `o-3po4htghbo`
whose management account is the owner's own sign-up. An organisation policy (SCP) admits ONE region for regional
services — the project's, `ap-southeast-2` (Sydney) — and the global ones: Route 53, CloudFront, ACM in `us-east-1`,
S3's global endpoint. CloudFormation is refused everywhere but Sydney. So:

- both stacks are deployed in `ap-southeast-2` (Route 53 and CloudFront are global; the stack only lives there);
- the bucket is in Sydney (CloudFront serves from its edges, India included; the origin's place hardly matters);
- the certificate is requested in `us-east-1` with the CLI (CloudFront takes certificates only from there, and the
  policy admits ACM there but not CloudFormation) and handed to `site.yaml` as `CertificateArn`.

The CLI is signed in with `aws login` (browser; short-lived credentials renewed by themselves for up to 90 days).

## What it costs

Route 53 zone US$0.50 a month plus queries; S3 and CloudFront for a site this size stay within cents (CloudFront's
always-free tier is 1 TB and 10 million requests a month); the certificate is free.

## Steps (from `C:\Users\gupta\projects\clarv-site`)

1. **Zone** — DONE 4 Oct 2026: stack `clarv-zone` in ap-southeast-2, hosted zone `Z0515255HQA5KHH31O3D`, read back
   from an AWS nameserver identical to the live Squarespace zone (A, AAAA, MX, SPF and apple-domain TXT, www, DKIM).

   ```
   aws cloudformation deploy --region ap-southeast-2 --stack-name clarv-zone --template-file aws/zone.yaml
   ```

2. **Certificate** — ISSUED 4 Oct 2026, 18:26:
   `arn:aws:acm:us-east-1:949836655208:certificate/e3f09165-baba-40bb-bb56-8d7d8037f71d`; its two validation
   CNAMEs are in the zone (parameters `CertValidation1Name/Value`, `CertValidation2Name/Value` on `clarv-zone`;
   ACM reuses the same validation records for the same name in the same account). **The first request failed with
   CAA_ERROR on www.clarv.in**: www was a CNAME to `guptaujjwal01.github.io`, and a CNAME carries its target's CAA
   records — github.io admits only Let's Encrypt, Sectigo and DigiCert. www now points at GitHub Pages by its
   addresses (A/AAAA), which lifts that; a CNAME cannot be swapped for other records in place, so the change was two
   updates (`WwwStage=none`, then `WwwStage=records`).

3. **Nameservers** — DONE 4 Oct 2026: Squarespace saved them at 18:07, the .in registry delegated to Route 53 at
   18:13. **DNSSEC first**: Squarespace had it on (a DS record at the registry). Its switch removes the signing keys
   at once and the registry's DS minutes later, so the domain failed validation (SERVFAIL at Google, Cloudflare,
   Quad9) from 17:56 to 18:03. Any future move off a signed zone: remove the DS at the registry, wait its TTL, and
   only then stop signing — or accept the gap. Squarespace's nameserver change also asks for an emailed code (the
   owner's). Squarespace's "Domain Connect" preset (`_domainconnect`) was not copied: it works only on its DNS.

**Steps 4–6 DONE 4 Oct 2026**: stack `clarv-site` (bucket `clarv-site-bucket-nsxy9daagnog`, distribution
`EAWMIJFSWBJIV` = `d42k2mgeq59m5.cloudfront.net`), the site uploaded and tested on the distribution as clarv.in
(pages 200, a missing page 404, www 301 to the apex with its path, http 301 to https, the ACM certificate verified,
HSTS / nosniff / frame-options / referrer headers present), and the four site records moved to CloudFront at 18:34
by an in-place UPSERT previewed first (Modify, Replacement False; mail records untouched). Squarespace's records
carried a 4-hour TTL, so resolvers that read them before 18:13 reach GitHub Pages until about 22:15 — and GitHub was
serving its `*.github.io` certificate for clarv.in, not one for the domain, so those visitors see a warning on
https until their cache expires. Retire GitHub Pages (step 7) only after that, on 5 Oct or later.

4. **Site stack**, once the certificate reads ISSUED
   (`aws acm describe-certificate --region us-east-1 --certificate-arn <arn> --query Certificate.Status`):

   ```
   aws cloudformation deploy --region ap-southeast-2 --stack-name clarv-site --template-file aws/site.yaml --parameter-overrides CertificateArn=<arn>
   ```

5. **Upload**: `powershell -ExecutionPolicy Bypass -File aws\deploy.ps1`; check it on the distribution's own address
   `https://<DistributionDomain>/` (the browser warns about the name; the page itself should load).

6. **Switch the site to CloudFront** (keep the certificate parameters on every later update of `clarv-zone`):

   ```
   aws cloudformation deploy --region ap-southeast-2 --stack-name clarv-zone --template-file aws/zone.yaml --parameter-overrides SiteTarget=cloudfront CloudFrontDomain=<DistributionDomain> CertValidation1Name=... CertValidation1Value=... CertValidation2Name=... CertValidation2Value=...
   ```

   When the Clarv application's stack is up, add `AppIp=<its PublicIp>`; that writes `app.clarv.in`.

7. **Retire GitHub Pages** once `https://clarv.in` answers from CloudFront (`Invoke-WebRequest https://clarv.in -Method
   Head` shows `Via: … cloudfront`): the repository's Settings › Pages › Unpublish. The repo stays the source; every
   later change is `git commit` then `aws\deploy.ps1`.

## The application (app.clarv.in)

The owner's rule (4 Oct 2026): when a customer signs in at clarv.in, everything runs on AWS, nothing on the
development PC. The application's kit is `vanij/deploy/` (docs/DEPLOY.md); it is region-agnostic (`--region`). It was
written for Mumbai, as the SP-API registration says; this project admits Sydney only. Mumbai needs the owner's
management account: a project in Asia Pacific (Mumbai), or Mumbai admitted on this project's region policy.

## What it sets

- The bucket is private, encrypted, versioned and kept if the stack is deleted; only this distribution can read it.
- HTTPS only (TLS 1.2 or later), HTTP/2 and HTTP/3, IPv6, AWS's managed security headers (HSTS, nosniff,
  frame-options, referrer policy).
- `www.clarv.in` answers 301 to `https://clarv.in` with the same path.
- Pages are re-checked on every visit, the stylesheet and logo kept a day; every upload clears CloudFront's cache.
