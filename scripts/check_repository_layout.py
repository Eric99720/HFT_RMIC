#!/usr/bin/env python3
"""Mechanical repository layout/governance checks for HFT_RMIC."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = [
    "AGENTS.md",
    "README.md",
    "CURRENT_PHASE.md",
    "TASKS.md",
    "PROGRESS.md",
    "DECISIONS.md",
    "CHANGELOG.md",
    "PLANS.md",
    "docs/README.md",
    "docs/project_state.json",
    "docs/project_management_workflow.md",
    "docs/repository_layout.md",
    "docs/results_policy.md",
    ".gitmodules",
]

FORBIDDEN_TRACKED_PREFIXES = ("build/", "reports/", "sim/", "waves/")
FORBIDDEN_SUFFIXES = (".jou", ".wdb", ".vcd", ".fst", ".dcp", ".bit", ".ltx")
BAD_NAME_RE = re.compile(r"(?:^|[-_.])(copy|backup|final\d+|new_new|status|ready|pending)(?:[-_.]|$)", re.I)
ALLOWED_STATUS_FILES = {"CURRENT_PHASE.md"}


def git_lines(*args: str) -> list[str]:
    cp = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=True)
    return [line for line in cp.stdout.splitlines() if line.strip()]


def main() -> int:
    errors: list[str] = []

    for rel in REQUIRED:
        if not (ROOT / rel).exists():
            errors.append(f"missing required file: {rel}")

    try:
        tracked = git_lines("ls-files")
    except Exception as exc:
        print(f"REPOSITORY_LAYOUT_CHECK_FAIL\ngit ls-files failed: {exc}")
        return 1

    for rel in tracked:
        norm = rel.replace("\\", "/")
        if norm.startswith(FORBIDDEN_TRACKED_PREFIXES):
            errors.append(f"generated/raw path must not be tracked: {norm}")
        if norm.lower().endswith(FORBIDDEN_SUFFIXES):
            errors.append(f"generated artifact suffix must not be tracked: {norm}")
        name = Path(norm).name
        if name not in ALLOWED_STATUS_FILES and BAD_NAME_RE.search(name):
            errors.append(f"noncanonical backup/status filename: {norm}")

    try:
        staged = git_lines("ls-files", "-s", "deps/RMIC", "deps/hft-full-system-fpga")
        for dep in ("deps/RMIC", "deps/hft-full-system-fpga"):
            rows = [x for x in staged if x.endswith("\t" + dep)]
            if len(rows) != 1 or not rows[0].startswith("160000 "):
                errors.append(f"dependency is not a single gitlink: {dep}")
    except Exception as exc:
        errors.append(f"unable to verify submodule gitlinks: {exc}")

    docs_index = ROOT / "docs" / "README.md"
    if docs_index.exists():
        text = docs_index.read_text(encoding="utf-8")
        for rel in ("project_management_workflow.md", "repository_layout.md", "results_policy.md"):
            if rel not in text:
                errors.append(f"docs/README.md missing index entry for {rel}")

    if errors:
        print("REPOSITORY_LAYOUT_CHECK_FAIL")
        for e in errors:
            print(e)
        return 1

    print("REPOSITORY_LAYOUT_CHECK_PASS")
    print(f"tracked_files={len(tracked)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
