#!/usr/bin/env python3
"""Attach-time checks, then commit the draft without releasing it.

msstore publish --noCommit uploads the MSIX but leaves Version empty. Partner
Center still shows the last live package until the draft is committed. This
script:

1. Fails if the draft has no PendingUpload package.
2. Sets TargetPublishMode=Manual so certification does not go live.
3. Commits the submission (msstore submission publish).
4. Waits until the Store extracts the new package version.

Right after commit, `msstore submission get` often exits -1 on Windows even
when the submission is fine. Treat that as transient; a successful commit is
enough for CI to pass.
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


def run_msstore(*args: str) -> tuple[int, str]:
    result = subprocess.run(
        ["msstore", *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return result.returncode, result.stdout or ""


def submission_json() -> dict:
    code, raw = run_msstore("submission", "get", APP_ID)
    start = raw.find("{")
    if start < 0:
        raise RuntimeError(
            f"msstore submission get failed (exit {code}): {raw.strip()[-500:]}"
        )
    return json.loads(raw[start:])


def print_packages(data: dict) -> list[dict]:
    packages = data.get("ApplicationPackages") or []
    print(f"Submission {data.get('Id')} Status={data.get('Status')}", flush=True)
    print("ApplicationPackages:", flush=True)
    for package in packages:
        print(
            f"  {package.get('FileStatus')} "
            f"{package.get('FileName')} {package.get('Version')}",
            flush=True,
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
    update = subprocess.run(
        ["msstore", "submission", "update", APP_ID, "--payload", payload],
        check=False,
    )
    if update.returncode != 0:
        raise SystemExit("msstore submission update failed.")
    published = subprocess.run(
        ["msstore", "submission", "publish", APP_ID],
        check=False,
    )
    if published.returncode != 0:
        raise SystemExit("msstore submission publish (commit) failed.")

    for attempt in range(1, POLL_ATTEMPTS + 1):
        try:
            data = submission_json()
        except Exception as exc:
            print(
                f"submission get not ready after commit "
                f"({attempt}/{POLL_ATTEMPTS}): {exc}",
                flush=True,
            )
            time.sleep(POLL_SECONDS)
            continue
        status = data.get("Status")
        packages = print_packages(data)
        if status in FAILED:
            raise SystemExit(f"Store submission failed: {status}")
        uploaded = [
            p
            for p in packages
            if p.get("FileStatus") in ("Uploaded", "PendingUpload")
            and p.get("Version")
        ]
        if uploaded:
            print(
                "Committed unpublished submission "
                f"(TargetPublishMode=Manual). Package {uploaded[0].get('Version')}.",
                flush=True,
            )
            return
        print(
            f"Waiting for Store to extract package version ({attempt}/{POLL_ATTEMPTS})",
            flush=True,
        )
        time.sleep(POLL_SECONDS)

    print(
        "Committed unpublished submission (TargetPublishMode=Manual). "
        "Store is still processing the package version.",
        flush=True,
    )


if __name__ == "__main__":
    sys.exit(main())
