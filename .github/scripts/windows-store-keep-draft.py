#!/usr/bin/env python3
"""Attach-time checks, then commit the draft without releasing it.

msstore publish --noCommit uploads the MSIX but leaves Version empty. Partner
Center still shows the last live package until the draft is committed. This
script:

1. Fails if the draft has no PendingUpload package.
2. Sets TargetPublishMode=Manual so certification does not go live.
3. Commits the submission (msstore submission publish).
4. Waits until the Store extracts the new package version.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time

APP_ID = "9MX4HKL30MWW"
POLL_SECONDS = 20
POLL_ATTEMPTS = 24
FAILED = frozenset(
    {
        "CommitFailed",
        "PreProcessingFailed",
        "CertificationFailed",
        "PublishFailed",
        "ReleaseFailed",
    }
)


def run_msstore(*args: str) -> str:
    return subprocess.check_output(
        ["msstore", *args],
        text=True,
        stderr=subprocess.STDOUT,
    )


def submission_json() -> dict:
    raw = run_msstore("submission", "get", APP_ID)
    start = raw.find("{")
    if start < 0:
        raise SystemExit("msstore submission get did not return JSON")
    return json.loads(raw[start:])


def print_packages(data: dict) -> list[dict]:
    packages = data.get("ApplicationPackages") or []
    print(f"Submission {data.get('Id')} Status={data.get('Status')}")
    print("ApplicationPackages:")
    for package in packages:
        print(
            f"  {package.get('FileStatus')} "
            f"{package.get('FileName')} {package.get('Version')}"
        )
    return packages


def main() -> None:
    data = submission_json()
    packages = print_packages(data)
    pending = [p for p in packages if p.get("FileStatus") == "PendingUpload"]
    if data.get("Status") == "Published" or not pending:
        raise SystemExit(
            "Draft has no PendingUpload package; the new MSIX was not attached."
        )

    data["TargetPublishMode"] = "Manual"
    payload = "store-submission.json"
    with open(payload, "w", encoding="utf-8") as handle:
        json.dump(data, handle)
    subprocess.check_call(
        ["msstore", "submission", "update", APP_ID, "--payload", payload]
    )
    subprocess.check_call(["msstore", "submission", "publish", APP_ID])

    for attempt in range(1, POLL_ATTEMPTS + 1):
        data = submission_json()
        status = data.get("Status")
        packages = print_packages(data)
        if status in FAILED:
            raise SystemExit(f"Store submission failed: {status}")
        versions = [p.get("Version") for p in packages if p.get("Version")]
        uploaded = [
            p
            for p in packages
            if p.get("FileStatus") in ("Uploaded", "PendingUpload") and p.get("Version")
        ]
        if uploaded:
            print(
                "Committed unpublished submission "
                f"(TargetPublishMode=Manual). Package {uploaded[0].get('Version')}."
            )
            return
        print(f"Waiting for Store to extract package version ({attempt}/{POLL_ATTEMPTS})")
        if not versions and attempt == POLL_ATTEMPTS:
            break
        time.sleep(POLL_SECONDS)

    raise SystemExit(
        "Committed the submission but the Store did not extract a package version."
    )


if __name__ == "__main__":
    sys.exit(main())
