#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

outputs = json.loads(Path(sys.argv[1]).read_text())
names = {"bucket_id": "bucket-id", "release_bucket_id": "release-bucket-id",
         "cloudfront_distribution_id": "distribution-id", "site_url": "site-url"}
with open(os.environ["GITHUB_OUTPUT"], "a") as target:
    for source, destination in names.items():
        if source in outputs:
            value = outputs[source]["value"]
            if not isinstance(value, str) or "\n" in value or "\r" in value:
                raise ValueError(f"Unexpected Terraform output {source}")
            target.write(f"{destination}={value}\n")
