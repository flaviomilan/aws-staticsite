#!/usr/bin/env python3
"""Verify HTTPS/security headers and prove a private S3 origin is inaccessible."""
import json
import subprocess
import sys
import urllib.error
import urllib.request


def check(url, distribution_id):
    if not url.startswith("https://"):
        raise ValueError("Smoke checks require an HTTPS URL")
    with urllib.request.urlopen(url, timeout=30) as response:
        if not response.geturl().startswith("https://"):
            raise ValueError("Homepage redirected away from HTTPS")
        if response.status != 200 or "text/html" not in response.headers.get("Content-Type", ""):
            raise ValueError("Homepage did not return HTML with HTTP 200")
        for name in ("Strict-Transport-Security", "Content-Security-Policy", "X-Content-Type-Options"):
            if not response.headers.get(name):
                raise ValueError(f"Missing security header: {name}")
    distribution = json.loads(subprocess.check_output([
        "aws", "--no-cli-pager", "cloudfront", "get-distribution", "--id", distribution_id], text=True))
    for origin in distribution["Distribution"]["DistributionConfig"]["Origins"]["Items"]:
        if not origin.get("OriginAccessControlId"):
            raise ValueError("Origin is missing OAC")
        try:
            urllib.request.urlopen(f"https://{origin['DomainName']}/index.html", timeout=30)
        except urllib.error.HTTPError as error:
            if error.code == 403:
                continue
            raise
        raise ValueError("S3 object is accessible without CloudFront")
    print("HTTPS, security headers and private origin verified")


if __name__ == "__main__":
    check(*sys.argv[1:])
