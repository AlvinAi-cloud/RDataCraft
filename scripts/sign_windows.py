#!/usr/bin/env python3
"""Sign and verify one Windows installer/uninstaller using an existing certificate store.

The certificate thumbprint is public metadata. Private keys stay with the configured
Windows certificate provider. This tool does not import keys or accept passwords.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import urlsplit


def signing_command(tool, certificate, timestamp, file):
    if not re.fullmatch(r"[0-9A-Fa-f]{40}", certificate):
        raise ValueError("Expected a certificate SHA-1 thumbprint (40 hexadecimal characters).")
    url = urlsplit(timestamp)
    if url.scheme != "https" or not url.hostname or url.username or url.password or re.search(r'[\s\"\x27&|<>%!?]', timestamp):
        raise ValueError("Expected a plain HTTPS timestamp-service URL supplied by your certificate provider.")
    return [str(tool), "sign", "/sha1", certificate, "/s", "My", "/fd", "SHA256",
            "/tr", timestamp, "/td", "SHA256", str(file)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--certificate", required=True)
    parser.add_argument("--timestamp-url", required=True)
    parser.add_argument("--signtool", default="signtool.exe")
    parser.add_argument("--plan", action="store_true")
    args = parser.parse_args()
    try:
        command = signing_command(args.signtool, args.certificate, args.timestamp_url, args.file)
    except ValueError as error:
        parser.error(str(error))
    if args.plan:
        print(command)
        return
    if os.name != "nt" or not args.file.is_file():
        parser.error("Run on Windows with an existing installer or NSIS-generated uninstaller.")
    tool = shutil.which(args.signtool)
    if not tool:
        parser.error("Install the Windows SDK and make SignTool available, or use --signtool.")
    command[0] = tool
    subprocess.run(command, check=True)
    subprocess.run([tool, "verify", "/pa", "/all", "/tw", str(args.file)], check=True)
    # SignTool can warn on missing timestamps. Require a trusted, timestamped
    # signature from this exact signer, rather than accepting a warning as success.
    environment = dict(os.environ, RDATACRAFT_SIGNED_FILE=str(args.file.resolve()),
                       RDATACRAFT_CERTIFICATE=args.certificate)
    script = """$ErrorActionPreference='Stop';
    $s=Get-AuthenticodeSignature -LiteralPath $env:RDATACRAFT_SIGNED_FILE;
    if ($s.Status -ne 'Valid' -or !$s.TimeStamperCertificate -or
        $s.SignerCertificate.Thumbprint -ne $env:RDATACRAFT_CERTIFICATE) {
      throw 'A trusted, timestamped signature from the selected certificate is required.'
    }"""
    subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script], env=environment, check=True)


if __name__ == "__main__":
    main()
