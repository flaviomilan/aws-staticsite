#!/usr/bin/env python3
"""Install pinned Linux/amd64 verification tools with recorded SHA-256 checksums."""
import hashlib
import io
import sys
import tarfile
import urllib.request
from pathlib import Path

TOOLS = {
    "actionlint": (
        "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz",
        "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"),
    "trivy": (
        "https://github.com/aquasecurity/trivy/releases/download/v0.75.0/trivy_0.75.0_Linux-64bit.tar.gz",
        "c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f"),
}


if __name__ == "__main__":
    destination = Path(sys.argv[1])
    destination.mkdir(parents=True, exist_ok=True)
    for name in sys.argv[2:]:
        url, checksum = TOOLS[name]
        request = urllib.request.Request(url, headers={"User-Agent": "aws-staticsite-checks"})
        data = urllib.request.urlopen(request, timeout=60).read()
        if hashlib.sha256(data).hexdigest() != checksum:
            raise ValueError(f"Checksum mismatch for {name}")
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            member = next(item for item in archive.getmembers() if item.name in (name, f"./{name}"))
            target = destination / name
            target.write_bytes(archive.extractfile(member).read())
            target.chmod(0o755)
