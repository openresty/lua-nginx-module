#!/usr/bin/env python3
"""Loopback TCP fixture for socket-on-push.t (Python standard library only)."""

import socket
import socketserver
import threading


class Peer:
    def __init__(self, sock):
        self.sock = sock
        self.received = b""
        self.closed = False
        self.changed = threading.Condition()

    def wait(self, predicate):
        with self.changed:
            if not self.changed.wait_for(predicate, timeout=3):
                raise TimeoutError("peer did not reach the expected state")


peers = {}
peers_lock = threading.Lock()


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.request.settimeout(5)
        self.request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        peer = None
        try:
            command = self.rfile.readline().decode().strip().split()
            if command[0] == "OPEN":
                peer = Peer(self.request)
                with peers_lock:
                    peers[command[1]] = peer
                self.wfile.write(b"READY\n")
                while True:
                    data = self.request.recv(65536)
                    if not data:
                        break
                    with peer.changed:
                        peer.received += data
                        peer.changed.notify_all()
                return

            if command != ["CONTROL"]:
                raise ValueError("expected OPEN or CONTROL")
            for line in self.rfile:
                command = line.decode().strip().split()
                with peers_lock:
                    target = peers[command[1]]
                if command[0] == "SEND":
                    target.sock.sendall(bytes.fromhex(command[2]))
                elif command[0] == "EXPECT":
                    expected = bytes.fromhex(command[2])
                    target.wait(lambda: len(target.received) >= len(expected)
                                or target.closed)
                    with target.changed:
                        actual = target.received[:len(expected)]
                        if actual != expected:
                            raise ValueError("reply mismatch: " + repr(actual))
                        target.received = target.received[len(expected):]
                elif command[0] == "CLOSED":
                    target.wait(lambda: target.closed)
                elif command[0] == "CLOSE":
                    target.sock.shutdown(socket.SHUT_RDWR)
                else:
                    raise ValueError("unknown command")
                self.wfile.write(b"OK\n")
        except (OSError, ValueError, KeyError, IndexError) as exc:
            try:
                self.wfile.write(("ERROR " + str(exc) + "\n").encode())
            except OSError:
                pass
        finally:
            if peer is not None:
                with peer.changed:
                    peer.closed = True
                    peer.changed.notify_all()


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", 0), Handler) as server:
        print(server.server_address[1], flush=True)
        server.serve_forever()
