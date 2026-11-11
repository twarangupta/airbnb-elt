"""Fail if anything that looks like a secret is tracked by git.

Run locally with `make check-secrets` and in CI on every push.
It only checks files git tracks (`git ls-files`), so your gitignored .env and
key files outside the repo are never read.
Exit code 0 = clean, 1 = something to fix (each finding is printed).
"""

import re
import subprocess
import sys
from pathlib import Path

# Files that must never be tracked, whatever they contain.
# docs/ holds private study notes: only the path is checked, never the content.
FORBIDDEN_NAMES = re.compile(r"(^|/)(\.env|credentials)$|\.(p8|pem|key)$|^docs/")

# Text patterns that mean a real secret was pasted into a file.
SECRET_PATTERNS = {
    "private key block": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    "AWS access key id": re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b"),
    "AWS secret access key": re.compile(r"aws_secret_access_key\s*=\s*\S{20,}", re.I),
    "Snowflake password": re.compile(r"^\s*password\s*:", re.I | re.M),
}

# In profiles.yml, these connection fields must come from env_var(), never be typed in.
PROFILE_FIELDS = ("account", "user", "private_key_path", "private_key_passphrase", "password", "token")

# This file describes the patterns, so it is allowed to contain them.
SELF = "scripts/check_secrets.py"


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True)
    return [line for line in out.stdout.splitlines() if line]


def check_profile(path: str, text: str) -> list[str]:
    problems = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        match = re.match(r"\s*(\w+)\s*:\s*(.+?)\s*$", line)
        if match and match.group(1) in PROFILE_FIELDS and "env_var(" not in match.group(2):
            problems.append(f"{path}:{lineno}: '{match.group(1)}' is hard-coded; use env_var()")
    return problems


def main() -> int:
    problems: list[str] = []
    for path in tracked_files():
        if path == SELF:
            continue
        if FORBIDDEN_NAMES.search(path):
            problems.append(f"{path}: this file must not be tracked by git")
            continue
        try:
            text = Path(path).read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError):
            continue  # binary or deleted file
        for name, pattern in SECRET_PATTERNS.items():
            if pattern.search(text):
                problems.append(f"{path}: looks like a {name}")
        if path.endswith("profiles.yml"):
            problems.extend(check_profile(path, text))

    if problems:
        print("Possible secrets found:")
        print("\n".join(f"  - {p}" for p in problems))
        return 1
    print("No secrets found in tracked files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
