#!/usr/bin/env python3
"""Publish/restore build artifacts using AWS CLI; no third-party Python packages."""
import argparse
import hashlib
import json
import mimetypes
import re
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path, PurePosixPath

RELEASE_ID = re.compile(r"^[0-9a-f]{40}$")
HASHED_ASSET = re.compile(r"[._-][0-9a-f]{8,}[._-]", re.I)
HTML_CACHE = "public,max-age=0,must-revalidate"
ASSET_CACHE = "public,max-age=31536000,immutable"
OTHER_CACHE = "public,max-age=300,must-revalidate"


def checksum(file):
    digest = hashlib.sha256()
    with file.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def aws(*args):
    return subprocess.run(["aws", "--no-cli-pager", *args], check=True,
                          capture_output=True, text=True).stdout


def safe_path(value):
    path = PurePosixPath(value)
    if (not value or path.is_absolute() or ".." in path.parts or "\\" in value
            or any(ord(char) < 32 for char in value) or str(path) != value):
        raise ValueError(f"Unsafe object path: {value!r}")
    return path


def metadata(key):
    suffix = PurePosixPath(key).suffix.lower()
    content_type = {".js": "application/javascript", ".mjs": "application/javascript",
                    ".wasm": "application/wasm", ".webmanifest": "application/manifest+json"}.get(
                        suffix, mimetypes.guess_type(key)[0] or "application/octet-stream")
    if suffix in (".html", ".htm"):
        content_type += "; charset=utf-8"
        cache = HTML_CACHE
    elif HASHED_ASSET.search(PurePosixPath(key).name):
        cache = ASSET_CACHE
    else:
        cache = OTHER_CACHE
    return content_type, cache


def inventory(directory):
    directory = directory.resolve()
    if not directory.is_dir():
        raise ValueError("Build directory does not exist")
    result = []
    for file in sorted(directory.rglob("*")):
        if file.is_symlink():
            raise ValueError(f"Symlinks are not allowed in artifacts: {file}")
        if not file.is_file():
            continue
        key = file.relative_to(directory).as_posix()
        safe_path(key)
        if any(part.startswith(".") and part != ".well-known" for part in PurePosixPath(key).parts):
            raise ValueError(f"Hidden files are not publishable: {key}")
        content_type, cache = metadata(key)
        result.append({"path": key, "sha256": checksum(file),
                       "content_type": content_type, "cache_control": cache})
    if not any(item["path"] == "index.html" for item in result):
        raise ValueError("Artifact must contain index.html")
    return result


def read_json_object(bucket, key):
    try:
        return json.loads(aws("s3", "cp", f"s3://{bucket}/{key}", "-", "--only-show-errors"))
    except subprocess.CalledProcessError as error:
        if "NoSuchKey" in error.stderr or "(404)" in error.stderr:
            return None
        raise


def put_json(bucket, key, value, temporary):
    file = temporary / "metadata.json"
    file.write_text(json.dumps(value, sort_keys=True))
    aws("s3", "cp", str(file), f"s3://{bucket}/{key}", "--content-type", "application/json",
        "--cache-control", "no-store", "--only-show-errors")


def validate_manifest(manifest, release_id):
    if not isinstance(manifest, dict) or manifest.get("release_id") != release_id or manifest.get("version") != 1:
        raise ValueError("Invalid release manifest")
    entries = manifest.get("files")
    if not isinstance(entries, list) or not entries:
        raise ValueError("Release manifest has no files")
    seen = set()
    for entry in entries:
        key = entry["path"]
        safe_path(key)
        if key in seen or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]):
            raise ValueError("Duplicate path or invalid checksum in release manifest")
        seen.add(key)
        if (entry["content_type"], entry["cache_control"]) != metadata(key):
            raise ValueError("Unexpected object metadata in release manifest")
    if "index.html" not in seen:
        raise ValueError("Release is missing index.html")


def run(args):
    if not RELEASE_ID.fullmatch(args.release_id):
        raise ValueError("release-id must be a full 40-character Git commit SHA")
    if args.bucket == args.release_bucket:
        raise ValueError("The archive must use a separate private bucket")
    prefix = f"releases/{args.release_id}"
    with tempfile.TemporaryDirectory(prefix="static-site-") as tmp:
        temporary = Path(tmp)
        if args.command == "publish":
            directory = Path(args.directory).resolve()
            manifest = {"version": 1, "release_id": args.release_id, "files": inventory(directory)}
            existing = read_json_object(args.release_bucket, f"{prefix}/manifest.json")
            if existing is not None and existing != manifest:
                raise ValueError("Release SHA already exists with different content; create a new commit")
            if existing is None:
                def archive(entry):
                    file = directory / entry["path"]
                    if checksum(file) != entry["sha256"]:
                        raise ValueError(f"Artifact changed during archival: {entry['path']}")
                    aws("s3", "cp", str(directory / entry["path"]),
                        f"s3://{args.release_bucket}/{prefix}/objects/{entry['path']}", "--only-show-errors")
                with ThreadPoolExecutor(max_workers=8) as workers:
                    list(workers.map(archive, manifest["files"]))
                # Completion marker is written only after every archive object succeeds.
                put_json(args.release_bucket, f"{prefix}/manifest.json", manifest, temporary)
        else:
            manifest = read_json_object(args.release_bucket, f"{prefix}/manifest.json")
            validate_manifest(manifest, args.release_id)
            directory = temporary / "restored"
            directory.mkdir()
            for entry in manifest["files"]:
                target = directory / str(safe_path(entry["path"]))
                target.parent.mkdir(parents=True, exist_ok=True)
                aws("s3", "cp", f"s3://{args.release_bucket}/{prefix}/objects/{entry['path']}",
                    str(target), "--only-show-errors")
                if checksum(target) != entry["sha256"]:
                    raise ValueError(f"Archive checksum mismatch: {entry['path']}")
        # Keep previous assets: cached HTML may still refer to them. HTML always goes last.
        def copy_live(entry):
            # Verify again before publishing, catching a modified build directory.
            file = directory / entry["path"]
            if checksum(file) != entry["sha256"]:
                raise ValueError(f"Artifact changed during publication: {entry['path']}")
            aws("s3", "cp", str(file), f"s3://{args.bucket}/{entry['path']}",
                "--content-type", entry["content_type"], "--cache-control", entry["cache_control"],
                "--only-show-errors")
        # Bounded concurrency within each phase speeds larger sites without exposing
        # HTML before its dependencies have finished uploading.
        assets = [entry for entry in manifest["files"] if PurePosixPath(entry["path"]).suffix.lower() not in (".html", ".htm")]
        html = [entry for entry in manifest["files"] if PurePosixPath(entry["path"]).suffix.lower() in (".html", ".htm") and entry["path"] != "index.html"]
        for phase in (assets, html):
            with ThreadPoolExecutor(max_workers=8) as workers:
                list(workers.map(copy_live, phase))
        copy_live(next(entry for entry in manifest["files"] if entry["path"] == "index.html"))
        invalidation = json.loads(aws("cloudfront", "create-invalidation", "--distribution-id",
                                      args.distribution_id, "--paths", "/*"))
        aws("cloudfront", "wait", "invalidation-completed", "--distribution-id", args.distribution_id,
            "--id", invalidation["Invalidation"]["Id"])
        # Marker denotes a finished publication, never an interrupted one.
        put_json(args.release_bucket, "current.json", {"release_id": args.release_id}, temporary)
    print(f"{args.command} completed: {args.release_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("publish", "rollback"))
    for name in ("bucket", "release-bucket", "distribution-id", "release-id"):
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument("--directory")
    args = parser.parse_args()
    if args.command == "publish" and not args.directory:
        parser.error("publish requires --directory")
    run(args)


if __name__ == "__main__":
    main()
