# 🌍 CDN & Edge Networking

CloudFront, caching strategies, origins, edge locations, and global content delivery.

---

## 📚 Table of Contents

- [1. What is a CDN?](#1-what-is-a-cdn)
- [2. How CDN Caching Works](#2-how-cdn-caching-works)
- [3. AWS CloudFront Deep Dive](#3-aws-cloudfront-deep-dive)
- [4. Cache Invalidation](#4-cache-invalidation)
- [5. CDN Security](#5-cdn-security)
- [6. Performance Optimization](#6-performance-optimization)
- [7. Other CDN Providers](#7-other-cdn-providers)
- [Cheatsheet](#cheatsheet)

---

## 1. What is a CDN?

A Content Delivery Network (CDN) distributes content across globally distributed **edge locations** (Points of Presence — PoPs). Users are served from the nearest edge, reducing latency.

```
Without CDN:
  User in Munich → request → Origin server in US-East-1
  Round trip: ~120ms (transatlantic)

With CDN:
  User in Munich → request → Edge PoP in Frankfurt
  Round trip: ~5ms (local)
  Edge serves cached content — origin not hit at all
```

### What CDNs deliver

- **Static assets** — HTML, CSS, JS, images, fonts, videos
- **API responses** — cacheable GET requests
- **Software downloads** — large files
- **Streaming** — video on demand, live streaming
- **Dynamic content** — via origin shield + smart routing

### CDN key metrics

| Metric | Description |
|--------|-------------|
| **Cache Hit Ratio** | % of requests served from edge (not origin) |
| **TTFB** | Time To First Byte — latency to first response byte |
| **Origin offload** | % of traffic NOT reaching origin |
| **Edge latency** | Time at the edge PoP |
| **Transfer time** | Time to download full response |

---

## 2. How CDN Caching Works

### Request flow

```
User → CDN Edge PoP
         │
         ├── Cache HIT  → return cached response immediately
         │
         └── Cache MISS → forward to Origin
                              │
                         Origin responds
                              │
                         Edge caches response
                              │
                         Return to user
                         (and serve from cache for future requests)
```

### Cache key

The cache key determines what makes a request "unique" for caching:

```
Default cache key:
  Host + URL path + query string

Example:
  Request: GET https://cdn.example.com/api/products?page=1&sort=price
  Cache key: cdn.example.com + /api/products + page=1&sort=price

Two requests with same cache key → same cached response

Custom cache key (CloudFront):
  Include/exclude query strings
  Include/exclude headers
  Include cookies
  Include geographic location
```

### Cache control headers

The origin server controls caching behavior via HTTP headers:

```
Cache-Control: max-age=3600
  → Cache for 3600 seconds (1 hour)

Cache-Control: no-cache
  → Must revalidate with origin before serving (but can store)

Cache-Control: no-store
  → Never cache (sensitive data)

Cache-Control: public, max-age=86400
  → Any cache (CDN, browser) can cache for 24 hours

Cache-Control: private, max-age=3600
  → Only browser cache (not CDN) — user-specific content

Cache-Control: s-maxage=3600
  → CDN cache for 3600s (overrides max-age for shared caches)

Surrogate-Control: max-age=3600
  → CDN-specific, not forwarded to browser

Vary: Accept-Encoding
  → Different cache for gzip vs brotli responses

ETag: "abc123"
Last-Modified: Mon, 15 Jan 2024 00:00:00 GMT
  → Used for conditional requests (304 Not Modified)
```

### CDN caching tiers

```
Browser cache     → user's local cache (private)
CDN Edge          → PoP closest to user
CDN Origin Shield → regional CDN cache (optional middle tier)
Origin server     → your server/S3/ALB
```

```
With Origin Shield:
  Multiple edges → single Origin Shield → Origin
  Reduces origin load dramatically for popular content
  One cache fill request to origin for many edge cache misses
```

---

## 3. AWS CloudFront Deep Dive

CloudFront is AWS's CDN with 450+ edge locations globally.

### Core concepts

```
Distribution  = your CloudFront configuration
Origin        = where CloudFront fetches content (S3, ALB, EC2, custom)
Behavior      = rules for routing requests to origins (by path)
Edge location = where content is cached (PoP)
Origin Shield = regional middle-tier cache (optional)
```

### Distribution with S3 + ALB

```hcl
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["www.example.com", "example.com"]

  # Origin 1: S3 for static assets
  origin {
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = "S3-static"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # Origin 2: ALB for API
  origin {
    domain_name = aws_lb.api.dns_name
    origin_id   = "ALB-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Optional: Origin Shield (reduces origin load)
    origin_shield {
      enabled              = true
      origin_shield_region = "eu-central-1"
    }
  }

  # Default behavior: serve static assets from S3
  default_cache_behavior {
    target_origin_id       = "S3-static"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id = aws_cloudfront_cache_policy.static.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_routing.arn
    }
  }

  # /api/* behavior: forward to ALB
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    target_origin_id = "ALB-api"
    viewer_protocol_policy = "https-only"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    # Forward all headers to origin (for API)
    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Accept"]
      cookies { forward = "none" }
    }
  }

  # TLS certificate (must be in us-east-1 for CloudFront)
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Geo restriction
  restrictions {
    geo_restriction {
      restriction_type = "none"
      # restriction_type = "whitelist"
      # locations        = ["DE", "AT", "CH"]
    }
  }

  # WAF integration
  web_acl_id = aws_wafv2_web_acl.cloudfront.arn

  tags = local.common_tags
}
```

### Cache policies

```hcl
# Cache policy for static assets (long TTL)
resource "aws_cloudfront_cache_policy" "static" {
  name    = "static-assets"
  comment = "Cache static assets for 1 year"

  default_ttl = 86400      # 1 day default
  max_ttl     = 31536000   # 1 year max
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}
```

### CloudFront Functions (edge compute)

```javascript
// Viewer request function — runs at every edge, ~1ms execution
// Use for: URL rewrites, A/B testing, auth header manipulation

function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // SPA routing — serve index.html for all non-file paths
    if (!uri.includes('.')) {
        request.uri = '/index.html';
    }

    // Add security headers
    request.headers['x-custom-header'] = { value: 'my-value' };

    return request;
}
```

```hcl
resource "aws_cloudfront_function" "spa_routing" {
  name    = "spa-routing"
  runtime = "cloudfront-js-2.0"
  code    = file("${path.module}/functions/spa-routing.js")
}
```

### Lambda@Edge (more powerful, higher latency)

```javascript
// Runs in regional edge caches (~10ms execution)
// Full Node.js runtime, can make network calls

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;

    // Validate JWT token
    const token = request.headers['authorization']?.[0]?.value;
    if (!token || !validateJWT(token)) {
        return {
            status: '401',
            body: JSON.stringify({ error: 'Unauthorized' })
        };
    }

    return request;
};
```

---

## 4. Cache Invalidation

### Invalidation strategies

```bash
# Invalidate specific paths in CloudFront
aws cloudfront create-invalidation \
  --distribution-id EXXXXXXXXXXXXX \
  --paths "/index.html" "/app.js" "/styles.css"

# Invalidate everything (slow, expensive)
aws cloudfront create-invalidation \
  --distribution-id EXXXXXXXXXXXXX \
  --paths "/*"

# Invalidation cost:
# First 1000 paths/month: free
# After: $0.005 per path

# Check invalidation status
aws cloudfront list-invalidations \
  --distribution-id EXXXXXXXXXXXXX
```

### Cache busting (better than invalidation)

```
Instead of invalidating, embed version in filename:
  app.js    → app.abc123.js   (content hash in filename)
  styles.css → styles.def456.css

index.html references the hashed filenames.
New deployment → new hashes → new filenames → cache miss automatically.
index.html itself has short TTL (60s) or is not cached.

Benefits:
  - No invalidation cost
  - Old and new versions coexist during rollout
  - Works for any CDN
  - Zero manual steps
```

### Stale-while-revalidate

```
Cache-Control: max-age=60, stale-while-revalidate=300

Behavior:
  - Serve from cache for 60 seconds (fresh)
  - If > 60s but < 360s: serve stale immediately + revalidate in background
  - If > 360s: wait for fresh response

Benefits: zero latency even when cache is slightly stale
```

---

## 5. CDN Security

### Origin protection

```
Problem: Clients bypass CDN and hit origin directly
         → CDN WAF and rate limiting bypassed
         → Origin exposed directly to internet

Solution 1: Origin secret header
  CloudFront adds X-Origin-Secret: <random-token> to all requests
  ALB/nginx verifies this header, reject requests without it

Solution 2: AWS OriginAccessControl for S3
  S3 bucket policy only allows access from CloudFront OAC
  S3 is not public at all

Solution 3: IP whitelist
  Only allow CloudFront IP ranges on origin security group
  CloudFront publishes its IP list:
  curl https://ip-ranges.amazonaws.com/ip-ranges.json | jq '.prefixes[] | select(.service=="CLOUDFRONT") | .ip_prefix'
```

### HTTPS everywhere

```hcl
# Force HTTPS redirect
default_cache_behavior {
  viewer_protocol_policy = "redirect-to-https"
  # Options:
  # allow-all        → HTTP and HTTPS
  # https-only       → HTTPS only, HTTP gets error
  # redirect-to-https → HTTP redirects to HTTPS
}

# Minimum TLS version
viewer_certificate {
  minimum_protocol_version = "TLSv1.2_2021"
  # Options: TLSv1, TLSv1.1, TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2021
}
```

### Signed URLs and cookies

```python
# Generate signed URL (time-limited access to private content)
import boto3
from botocore.signers import CloudFrontSigner
from datetime import datetime, timedelta

def create_signed_url(url, key_id, private_key, expiry_hours=24):
    cf_signer = CloudFrontSigner(key_id, lambda msg: private_key.sign(msg))

    signed_url = cf_signer.generate_presigned_url(
        url,
        date_less_than=datetime.now() + timedelta(hours=expiry_hours)
    )
    return signed_url

# User accesses:
# https://cdn.example.com/videos/private-video.mp4?Policy=...&Signature=...&Key-Pair-Id=...
```

---

## 6. Performance Optimization

### HTTP/2 and HTTP/3

```
HTTP/1.1: one request per connection, head-of-line blocking
HTTP/2:   multiplexing — many requests over one connection
HTTP/3:   QUIC (UDP-based) — 0-RTT reconnect, better on mobile

CloudFront supports HTTP/2 and HTTP/3 (QUIC) automatically.
Enable HTTP/3:

resource "aws_cloudfront_distribution" "main" {
  http_version = "http3"
}
```

### Compression

```
CloudFront auto-compresses:
  - gzip: supported by all browsers
  - Brotli: better compression ratio, modern browsers

Enable:
parameters_in_cache_key_and_forwarded_to_origin {
  enable_accept_encoding_gzip   = true
  enable_accept_encoding_brotli = true
}

Files compressed at edge:
  HTML, CSS, JS, JSON, SVG → 70-90% size reduction
  Images (already compressed) → not compressed again
```

### Cache hit ratio optimization

```
Common cache hit ratio killers:

1. Too many cache key variations
   → Query string params that don't affect content
   Solution: exclude non-functional query strings from cache key

2. Short TTLs
   → Content expires before second request
   Solution: use content hashing + long TTL for static assets

3. Vary header too broad
   → Vary: User-Agent creates unique cache per browser
   Solution: only Vary on Accept-Encoding

4. POST requests
   → Not cacheable
   Solution: design APIs with GET for reads

Target: > 90% cache hit ratio for static assets
```

---

## 7. Other CDN Providers

| CDN | Strengths | Best for |
|-----|-----------|---------|
| **CloudFront** | AWS integration, Lambda@Edge | AWS workloads |
| **Cloudflare** | DDoS protection, Zero Trust, Workers | Security-focused, edge compute |
| **Fastly** | Real-time purging, VCL config | High-traffic, fast cache control |
| **Akamai** | Largest network, enterprise | Enterprise, media |
| **Azure CDN** | Azure integration | Azure workloads |
| **GCP CDN** | GCP integration, HTTP/3 | GCP workloads |

### Cloudflare Workers (edge compute)

```javascript
// Run JavaScript at 300+ edge locations globally
addEventListener('fetch', event => {
    event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
    const url = new URL(request.url);

    // A/B test: 50% get new feature
    if (Math.random() < 0.5) {
        url.searchParams.set('feature', 'new');
    }

    // Add security headers to all responses
    const response = await fetch(url.toString());
    const newResponse = new Response(response.body, response);
    newResponse.headers.set('X-Frame-Options', 'DENY');
    newResponse.headers.set('X-Content-Type-Options', 'nosniff');

    return newResponse;
}
```

---

## Cheatsheet

```bash
# CloudFront invalidation
aws cloudfront create-invalidation \
  --distribution-id EXXXXXXXXXXXXX \
  --paths "/index.html" "/app.*.js"

# Check distribution
aws cloudfront list-distributions | jq '.DistributionList.Items[] | {id: .Id, domain: .DomainName, status: .Status}'

# Check cache headers from origin
curl -I https://cdn.example.com/app.js
# Cache-Control: public, max-age=31536000, immutable   ← good for static
# X-Cache: Hit from cloudfront                         ← cache hit!

# Check CloudFront-specific response headers
curl -I https://cdn.example.com/
# X-Cache: Miss from cloudfront   ← cache miss
# X-Cache: Hit from cloudfront    ← cache hit
# X-Amz-Cf-Pop: FRA53-P3         ← served from Frankfurt

# Test from different locations (using proxies)
curl --proxy http://proxy.de:3128 https://example.com

# Check origin connectivity
curl -H "X-Origin-Secret: <token>" https://origin.example.com/health
```

---

*Next: [Interview Q&A →](./10-interview-qa.md)*
