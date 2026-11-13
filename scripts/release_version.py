#!/usr/bin/env python3
"""Choose a stable version and optionally reserve its tag atomically on GitHub."""
import argparse
import os
from pathlib import Path
import re
import subprocess

VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")


def parse_version(value):
    match = VERSION.fullmatch(value.removeprefix("v"))
    return tuple(map(int, match.groups())) if match else None


def choose_version(tags, requested="auto", commit_tags=()):
    stable = {tag: parse_version(tag) for tag in tags if tag.startswith("v") and parse_version(tag)}
    existing = [tag for tag in commit_tags if tag in stable]
    if existing:
        chosen = max(existing, key=lambda tag: stable[tag])
        if requested != "auto" and parse_version(requested) != stable[chosen]:
            raise ValueError("This commit already has a different release version.")
        return chosen
    latest = max(stable.values(), default=None)
    if requested != "auto":
        version = parse_version(requested)
        if version is None or requested.startswith("v"):
            raise ValueError("RELEASE_VERSION must be auto or a numeric version such as 1.1.0.")
        if latest and version <= latest:
            raise ValueError("RELEASE_VERSION must be newer than every existing stable tag; reset it to auto after an explicit release.")
    else:
        version = (latest[0], latest[1], latest[2] + 1) if latest else (1, 0, 0)
    return "v" + ".".join(map(str, version))


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", default="HEAD")
    parser.add_argument("--reserve", action="store_true", help="Atomically create the release tag using GH_TOKEN and GH_REPO")
    args = parser.parse_args()
    commit = git("rev-parse", "--verify", args.commit + "^{commit}")
    requested = Path("RELEASE_VERSION").read_text().strip()
    repo = os.environ.get("GH_REPO", "")
    if args.reserve and (not repo or not os.environ.get("GH_TOKEN")):
        parser.error("--reserve requires GH_REPO and GH_TOKEN")
    for _ in range(5):
        if args.reserve:
            # Re-read remote tags after a collision with another master-merge release.
            subprocess.run(["git", "fetch", "origin", "--tags", "--quiet"], check=True)
        tags = git("tag", "--list", "v*").splitlines()
        commit_tags = git("tag", "--points-at", commit).splitlines()
        tag = choose_version(tags, requested, commit_tags)
        if not args.reserve or tag in commit_tags:
            print(tag)
            return
        result = subprocess.run([
            "gh", "api", "--method", "POST", f"repos/{repo}/git/refs",
            "-f", f"ref=refs/tags/{tag}", "-f", f"sha={commit}",
        ], text=True, capture_output=True)
        if result.returncode == 0:
            print(tag)
            return
        if "Reference already exists" not in result.stdout + result.stderr:
            raise RuntimeError("Could not reserve release tag: " + result.stderr.strip())
    raise RuntimeError("Concurrent releases reserved the next tag repeatedly; rerun this workflow.")


if __name__ == "__main__":
    main()
