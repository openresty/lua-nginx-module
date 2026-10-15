"""Local TLS backend for init_by_lua cosocket tests."""

import socket
import ssl
import subprocess
import sys
from pathlib import Path


def verify_chain():
    """Create one intermediate so verify_depth=0 fails deterministically."""
    directory = Path(sys.argv[1]).parent
    key = sys.argv[3]  # Repository-owned test key; never copy or print it.
    intermediate = directory / "intermediate.crt"
    leaf = directory / "leaf.crt"
    for name, subject, ca, ca_key, serial, extensions in (
        ("intermediate", "/CN=OpenResty Test Intermediate", sys.argv[4],
         sys.argv[5], "7", "basicConstraints=critical,CA:TRUE\n"),
        ("leaf", "/CN=openresty.org", str(intermediate), key, "8",
         "basicConstraints=CA:FALSE\nsubjectAltName=DNS:openresty.org\n"),
    ):
        csr = directory / (name + ".csr")
        ext = directory / (name + ".ext")
        ext.write_text(extensions)
        subprocess.run(["openssl", "req", "-new", "-key", key,
                        "-subj", subject, "-out", str(csr)],
                       check=True, capture_output=True)
        subprocess.run(["openssl", "x509", "-req", "-in", str(csr),
                        "-CA", ca, "-CAkey", ca_key, "-set_serial", serial,
                        "-days", "1", "-extfile", str(ext),
                        "-out", str(directory / (name + ".crt"))],
                       check=True, capture_output=True)
    chain = directory / "chain.crt"
    chain.write_bytes(leaf.read_bytes() + intermediate.read_bytes())
    return str(chain)

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
certificate = verify_chain() if len(sys.argv) == 6 else sys.argv[2]
context.load_cert_chain(certificate, sys.argv[3])
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
    listener.bind(sys.argv[1])
    listener.listen(8)
    while True:
        client, _ = listener.accept()
        try:
            with context.wrap_socket(client, server_side=True) as connection:
                connection.settimeout(10)
                request = b""
                while b"\r\n\r\n" not in request and len(request) < 8192:
                    data = connection.recv(1024)
                    if not data:
                        break
                    request += data
                connection.sendall(
                    b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n"
                    b"Connection: close\r\n\r\n")
        except (OSError, ssl.SSLError):
            client.close()
