#!/usr/bin/env python3
"""Verify the new MSIX is on the Partner Center draft and keep it unpublished.

msstore publish --noCommit leaves Status=PendingCommit. Partner Center's live
listing still shows the last published package until someone submits the draft.
This script fails if that draft has no PendingUpload package, then sets
TargetPublishMode=Manual so a later Submit does not go live automatically.
"""

from __future__ import annotations

import json
import subprocess
import sys

APP_ID = "9MX4HKL30MWW"


def submission_json() -> dict:
    raw = subprocess.check_output(
        ["msstore", "submission", "get", APP_ID],
        text=True,
        stderr=subprocess.STDOUT,
    )
    start = raw.find("{")
    if start < 0:
        raise SystemExit("msstore submission get did not return JSON")
    return json.loads(raw[start:])


def main() -> None:
    data = submission_json()
    status = data.get("Status")
    packages = data.get("ApplicationPackages") or []
    print(f"Submission {data.get('Id')} Status={status}")
    print("ApplicationPackages:")
    for package in packages:
        print(
            f"  {package.get('FileStatus')} "
            f"{package.get('FileName')} {package.get('Version')}"
        )

    pending = [p for p in packages if p.get("FileStatus") == "PendingUpload"]
    if status == "Published" or not pending:
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
    print("Draft kept unpublished (PendingCommit). TargetPublishMode=Manual.")


if __name__ == "__main__":
    sys.exit(main())
