"""Create the RSA key pair that the DBT_SVC Snowflake user logs in with.

    make keypair

Writes the PRIVATE key to SNOWFLAKE_PRIVATE_KEY_PATH from .env (default
~/.snowflake/airbnb_elt_rsa_key.p8), outside the repo, encrypted with
SNOWFLAKE_PRIVATE_KEY_PASSPHRASE if that is set. Prints only the PUBLIC key
body (safe to share) to paste into RSA_PUBLIC_KEY in 01_setup.sql, and its
SHA-256 fingerprint to compare with DESC USER DBT_SVC (RSA_PUBLIC_KEY_FP).
Refuses to overwrite an existing key file.
"""

import base64
import hashlib
import os
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    load_dotenv(REPO_ROOT / ".env", override=False)
    default = Path.home() / ".snowflake" / "airbnb_elt_rsa_key.p8"
    path = Path(os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH") or default).expanduser()
    if REPO_ROOT in path.resolve().parents:
        print(f"Refusing to write a private key inside the repo: {path}", file=sys.stderr)
        return 2
    if path.exists():
        print(f"{path} already exists; not overwriting. Delete it first to rotate.", file=sys.stderr)
        return 1

    passphrase = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE", "")
    encryption = (
        serialization.BestAvailableEncryption(passphrase.encode())
        if passphrase
        else serialization.NoEncryption()
    )
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, encryption)
    )

    public_der = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    body = base64.b64encode(public_der).decode()
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(public_der).digest()).decode()

    print(f"Private key written to {path} ({'encrypted' if passphrase else 'NOT encrypted'}).")
    print(f"Set SNOWFLAKE_PRIVATE_KEY_PATH={path.as_posix()} in .env if it is not already.\n")
    print("Public key body (paste into RSA_PUBLIC_KEY in 01_setup.sql; this half is safe to share):")
    print(body)
    print(f"\nFingerprint (compare with RSA_PUBLIC_KEY_FP in DESC USER DBT_SVC): {fingerprint}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
