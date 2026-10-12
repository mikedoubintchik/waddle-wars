#!/usr/bin/env python3
"""Migrate the existing Android upload password into a passphrase-encrypted file.

This is a one-time, owner-interactive alternative to repeated Keychain reads.
No password/passphrase is printed, put in argv, persisted raw, or inherited by
Godot/Gradle. The original Keychain item and upload key remain unchanged.
"""
from __future__ import annotations

import argparse
import base64
import getpass
import hmac
import json
import os
from pathlib import Path
import subprocess
import tempfile

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

import android_upload_signing as signing

SOURCE = Path(__file__).with_name("android_read_upload_password.swift").absolute()
OWN_SOURCE = Path(__file__).absolute()
VAULT_NAME = "android-upload-password-v1.json"
PASSWORD_ENV = "WADDLE_WARS_UPLOAD_PASSWORD"
SCHEMA = {"version", "bundle_id", "encrypted_key_sha256", "upload_certificate_sha256",
          "salt", "nonce", "ciphertext"}


def _decode(value: str, length: int) -> bytes:
    if not isinstance(value, str):
        raise signing.SigningError("Encrypted password file has invalid fields")
    try:
        result = base64.b64decode(value, validate=True)
    except ValueError:
        raise signing.SigningError("Encrypted password file has invalid fields") from None
    if len(result) != length:
        raise signing.SigningError("Encrypted password file has invalid fields")
    return result


def _key(passphrase: str, salt: bytes) -> bytes:
    if not isinstance(passphrase, str) or len(passphrase) < 16:
        raise signing.SigningError("Vault passphrase must have at least 16 characters")
    return Scrypt(salt=salt, length=32, n=2**17, r=8, p=1).derive(passphrase.encode("utf-8"))


def _aad(receipt: dict) -> bytes:
    return (signing.BUNDLE + "\n" + receipt["encrypted_key_sha256"] + "\n"
            + receipt["upload_certificate_sha256"]).encode("ascii")


def encrypt(password: bytes, passphrase: str, receipt: dict) -> dict:
    if (len(password) != 64 or
            len(base64.b64decode(password, validate=True)) != 48):
        raise signing.SigningError("Existing upload password has invalid format")
    salt, nonce = os.urandom(16), os.urandom(12)
    ciphertext = AESGCM(_key(passphrase, salt)).encrypt(nonce, password, _aad(receipt))
    return {"version": 1, "bundle_id": signing.BUNDLE,
            "encrypted_key_sha256": receipt["encrypted_key_sha256"],
            "upload_certificate_sha256": receipt["upload_certificate_sha256"],
            "salt": base64.b64encode(salt).decode("ascii"),
            "nonce": base64.b64encode(nonce).decode("ascii"),
            "ciphertext": base64.b64encode(ciphertext).decode("ascii")}


def decrypt(document: dict, passphrase: str, receipt: dict) -> bytes:
    if (not isinstance(document, dict) or set(document) != SCHEMA
            or type(document["version"]) is not int or document["version"] != 1
            or document["bundle_id"] != signing.BUNDLE
            or document["encrypted_key_sha256"] != receipt["encrypted_key_sha256"]
            or document["upload_certificate_sha256"] != receipt["upload_certificate_sha256"]):
        raise signing.SigningError("Encrypted password file does not match existing upload key")
    salt, nonce = _decode(document["salt"], 16), _decode(document["nonce"], 12)
    if not isinstance(document["ciphertext"], str) or len(document["ciphertext"]) > 256:
        raise signing.SigningError("Encrypted password file has invalid fields")
    try:
        ciphertext = base64.b64decode(document["ciphertext"], validate=True)
        password = AESGCM(_key(passphrase, salt)).decrypt(nonce, ciphertext, _aad(receipt))
        if len(password) != 64 or len(base64.b64decode(password, validate=True)) != 48:
            raise ValueError()
        return password
    except (InvalidTag, ValueError, TypeError):
        raise signing.SigningError("Vault passphrase or encrypted password is invalid") from None


def read_existing_password() -> bytes:
    signing.regular(SOURCE)
    with tempfile.TemporaryDirectory(prefix="waddle-password-migrate-") as directory:
        executable = Path(directory) / "read-password"
        compiled = subprocess.run(["/usr/bin/swiftc", str(SOURCE), "-o", str(executable)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90)
        if compiled.returncode:
            raise signing.SigningError("Private Keychain reader compilation failed")
        read_fd, write_fd = os.pipe()
        try:
            checked = subprocess.run([str(executable), str(write_fd)], pass_fds=(write_fd,),
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            os.close(write_fd)
            write_fd = -1
            password = os.read(read_fd, 65)
            if checked.returncode or len(password) != 64:
                raise signing.SigningError("Existing Android password unavailable in Keychain")
            return password
        finally:
            os.close(read_fd)
            if write_fd >= 0:
                os.close(write_fd)


def validate_password(jdk: Path, password: bytes, directory: Path, receipt: dict) -> None:
    signing.jdk_tools(jdk)
    signing.private_directory(directory)
    store = signing.regular(directory / "primary/upload.p12", private=True)
    if signing.digest(store) != receipt["encrypted_key_sha256"]:
        raise signing.SigningError("Existing upload key changed")
    env = signing.clean_environment(jdk)
    env[PASSWORD_ENV] = password.decode("ascii")
    with tempfile.TemporaryDirectory(prefix="waddle-upload-cert-") as temporary:
        certificate = Path(temporary).resolve() / "cert.der"
        command = [str(jdk / "bin/keytool"), "-exportcert", "-keystore", str(store),
                   "-storetype", "PKCS12", "-alias", signing.ALIAS,
                   "-storepass:env", PASSWORD_ENV, "-file", str(certificate)]
        try:
            result = subprocess.run(command, env=env, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, timeout=60)
        except (OSError, subprocess.SubprocessError):
            raise signing.SigningError("Existing upload key validation failed") from None
        if result.returncode or not certificate.is_file() or signing.digest(certificate) != receipt["upload_certificate_sha256"]:
            raise signing.SigningError("Existing upload password or certificate does not match")


def vault_path(directory: Path) -> Path:
    return directory / VAULT_NAME


def migrate(jdk: Path, passphrase: str) -> Path:
    directory, receipt = signing.load_signing_receipt()
    path = vault_path(directory)
    signing.safe_path(path)
    if path.exists():
        raise signing.SigningError("Encrypted password file already exists; no overwrite")
    password = read_existing_password()
    validate_password(jdk, password, directory, receipt)
    document = encrypt(password, passphrase, receipt)
    if not hmac.compare_digest(decrypt(document, passphrase, receipt), password):
        raise signing.SigningError("Encrypted password self-check failed")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(document, stream, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    signing.regular(path, private=True)
    return path


def unlock(directory: Path, receipt: dict, passphrase: str) -> tuple[bytes, str]:
    path = signing.regular(vault_path(directory), private=True)
    if path.stat().st_size > 1024:
        raise signing.SigningError("Encrypted password file is oversized")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        raise signing.SigningError("Encrypted password file is unreadable") from None
    return decrypt(document, passphrase, receipt), signing.digest(path)


def sign_aab(jdk: Path, directory: Path, unsigned: Path, signed: Path, password: bytes) -> dict:
    signing.jdk_tools(jdk)
    signing.private_directory(signed.parent)
    signing.regular(unsigned)
    signing.safe_path(signed)
    if signed.exists() or unsigned == signed or signed.suffix != ".aab" or unsigned.suffix != ".aab":
        raise signing.SigningError("Fresh distinct AAB output required")
    store = signing.regular(directory / "primary/upload.p12", private=True)
    env = signing.clean_environment(jdk)
    env[PASSWORD_ENV] = password.decode("ascii")
    command = [str(jdk / "bin/jarsigner"), "-keystore", str(store), "-storetype", "PKCS12",
               "-storepass:env", PASSWORD_ENV, "-keypass:env", PASSWORD_ENV,
               "-sigalg", "SHA256withRSA", "-digestalg", "SHA-256", "-signedjar", str(signed),
               str(unsigned), signing.ALIAS]
    try:
        result = subprocess.run(command, env=env, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=180)
    except (OSError, subprocess.SubprocessError):
        raise signing.SigningError("Direct PKCS12 signing failed; raw diagnostics discarded") from None
    if result.returncode or not signed.is_file():
        raise signing.SigningError("Direct PKCS12 signing failed; raw diagnostics discarded")
    signed.chmod(0o600)
    signing.regular(signed, private=True)
    return {"state": "sign_complete", "stage": "complete", "password_source": "encrypted_local_vault"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("migrate", choices=["migrate"])
    parser.add_argument("--jdk", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        first = getpass.getpass("New Android signing vault passphrase (16+ characters): ")
        second = getpass.getpass("Repeat vault passphrase: ")
        if not hmac.compare_digest(first, second):
            raise signing.SigningError("Vault passphrases differ")
        path = migrate(args.jdk, first)
        print(json.dumps({"state": "encrypted_android_password_vault_created", "path": str(path),
                          "vault_sha256": signing.digest(path), "keychain_item_changed": False,
                          "upload_key_changed": False}, indent=2))
        return 0
    except (KeyboardInterrupt, EOFError):
        print(json.dumps({"state": "migration_cancelled", "credential_changed": False}))
        return 1
    except signing.SigningError as error:
        print(json.dumps({"state": "migration_failed", "reason": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
