#!/usr/bin/env python3
"""Verify exact parent delegation and authoritative answers for a Route53 zone."""
import argparse
import subprocess
import time


def records(name, kind, server=None):
    # Parent servers return delegation in the AUTHORITY section, not ANSWER.
    command = ["dig", "+noall", "+answer", "+authority", "+time=3", "+tries=1"]
    if server:
        command += [f"@{server}"]
    command += [name, kind]
    result = set()
    for line in subprocess.check_output(command, text=True).splitlines():
        fields = line.split()
        if len(fields) >= 5 and fields[3] == kind and fields[0].lower().rstrip(".") == name.lower().rstrip("."):
            result.add(fields[4].lower().rstrip("."))
    return result


def delegated(domain, expected):
    # Query authoritative parent servers rather than accepting any recursive NS response.
    parent = domain.split(".", 1)[1]
    while parent:
        parents = records(parent, "NS", "1.1.1.1")
        if parents:
            break
        parent = parent.split(".", 1)[1] if "." in parent else ""
    if not parents:
        return False
    if any(records(domain, "NS", server) != expected for server in parents):
        return False
    return all(records(domain, "NS", server) == expected for server in expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--domain", required=True)
    parser.add_argument("--nameservers", nargs="+", required=True)
    parser.add_argument("--attempts", type=int, default=10)
    parser.add_argument("--interval", type=int, default=30)
    args = parser.parse_args()
    expected = {name.lower().rstrip(".") for name in args.nameservers}
    if "." not in args.domain or not expected:
        parser.error("A zone domain and expected nameservers are required")
    for attempt in range(args.attempts):
        try:
            if delegated(args.domain.rstrip("."), expected):
                print("Route53 delegation verified")
                return
        except subprocess.CalledProcessError:
            pass
        if attempt + 1 < args.attempts:
            time.sleep(args.interval)
    raise SystemExit("Delegation does not match Route53. Fix registrar/parent NS and rerun; no apply performed.")


if __name__ == "__main__":
    main()
