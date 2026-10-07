#!/usr/bin/env python3
"""Reject replacement/deletion of the resources an infrastructure migration must preserve."""
import json
import sys

PROTECTED = {"aws_s3_bucket", "aws_route53_zone", "aws_cloudfront_distribution"}


def destructive_changes(plan):
    return [change["address"] for change in plan.get("resource_changes", [])
            if change["type"] in PROTECTED and "delete" in change["change"]["actions"]]


if __name__ == "__main__":
    changes = destructive_changes(json.load(sys.stdin))
    if changes:
        sys.exit("Protected resources would be removed/replaced: " + ", ".join(changes))
