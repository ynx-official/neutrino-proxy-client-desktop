"""Generate disposable localhost TLS fixtures accepted by Windows and macOS."""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile


def main():
    openssl = os.environ.get("OPENSSL") or shutil.which("openssl")
    if openssl is None and os.name == "nt":
        candidate = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/usr/bin/openssl.exe"
        if candidate.is_file():
            openssl = str(candidate)
    if openssl is None:
        raise SystemExit("OpenSSL is required (Git for Windows bundles it).")
    output = Path(__file__).resolve().parents[1] / "test/fixtures/tls"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="neutrino-test-ca-") as directory:
        temporary = Path(directory)
        ca_key = temporary / "ca-key.pem"
        request = temporary / "server.csr"
        extensions = temporary / "server.ext"
        extensions.write_text(
            "basicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\n"
            "subjectKeyIdentifier=hash\n"
            "authorityKeyIdentifier=keyid,issuer\n"
            "subjectAltName=DNS:localhost\n", encoding="ascii")

        def run(*args):
            result = subprocess.run(
                [openssl, *map(str, args)], capture_output=True, text=True)
            if result.returncode:
                print(result.stdout, file=sys.stderr)
                print(result.stderr, file=sys.stderr)
                result.check_returncode()

        subprocess.run([openssl, "version"], check=True)

        run("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
            "-days", "3650", "-subj", "/CN=Neutrino Local Test CA",
            "-addext", "basicConstraints=critical,CA:TRUE",
            "-addext", "keyUsage=critical,keyCertSign,cRLSign",
            "-addext", "subjectKeyIdentifier=hash",
            "-keyout", ca_key, "-out", output / "ca.pem")
        run("req", "-new", "-newkey", "rsa:2048", "-nodes", "-sha256",
            "-subj", "/CN=localhost", "-keyout", output / "server-key.pem",
            "-out", request)
        # Apple evaluates custom TLS anchors too: use a real leaf certificate,
        # serverAuth EKU and a lifetime below its 825-day limit.
        run("x509", "-req", "-in", request, "-CA", output / "ca.pem",
            "-CAkey", ca_key, "-set_serial", "2", "-days", "365", "-sha256",
            "-extfile", extensions, "-out", output / "server.pem")
        run("verify", "-CAfile", output / "ca.pem", "-purpose", "sslserver",
            "-verify_hostname", "localhost", output / "server.pem")
    print("Generated test-only CA, localhost certificate and private key (365-day leaf).")


if __name__ == "__main__":
    main()
