#!/usr/bin/env python3
"""Fail CI early if an executable root is configured with local/unlocked state."""
import re
import sys
from pathlib import Path


def check(directory, config):
    root = Path(directory)
    content = "\n".join(file.read_text() for file in root.glob("*.tf"))
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    content = re.sub(r"(?m)^\s*(?:#|//).*$", "", content)
    backends = re.findall(r'backend\s+"([^"]+)"\s*\{', content)
    if backends != ["s3"]:
        raise ValueError("CI requires exactly one S3 backend; remove local backend overrides")
    settings = (root / config).read_text()
    settings = re.sub(r"(?m)^\s*(?:#|//).*$", "", settings)
    if not re.search(r"(?m)^\s*use_lockfile\s*=\s*true\s*(?:#.*)?$", settings):
        raise ValueError("Backend configuration must explicitly set use_lockfile=true")
    if not re.search(r"(?m)^\s*encrypt\s*=\s*true\s*(?:#.*)?$", settings):
        raise ValueError("Backend configuration must explicitly set encrypt=true")
    for key in ("bucket", "key", "region"):
        if not re.search(rf'(?m)^\s*{key}\s*=\s*"[^"\n]+"', settings):
            raise ValueError(f"Missing backend setting: {key}")


if __name__ == "__main__":
    check(*sys.argv[1:])
