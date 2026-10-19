"""Fake NATS server that streams preformatted MSG frames as fast as the socket allows.

It measures the subscriber in isolation, a real server limits delivery to a few million msgs/s.

    python3 fake_server.py --port 4333 --msgs 5000000 --size 3

Handles one client: replies to PING, waits for SUB and the following PING, then sends `msgs` messages
to the subscribed sid and keeps the connection open until the client closes it.
"""

import argparse
import json
import socket
import threading
import time

p = argparse.ArgumentParser()
p.add_argument("--port", type=int, default=4333)
p.add_argument("--msgs", type=int, default=5_000_000)
p.add_argument("--size", type=int, default=3)
p.add_argument("--subject", default="foo")
p.add_argument("--loops", type=int, default=1, help="number of clients to serve")
args = p.parse_args()

info = {
    "server_id": "FAKE", "server_name": "fake", "version": "2.10.0", "go": "go1.22", "host": "127.0.0.1",
    "port": args.port, "headers": True, "max_payload": 64 * 1024 * 1024, "proto": 1,
}


def serve(conn):
    send_lock = threading.Lock()
    subscribed = threading.Event()
    sid_box = {}

    def send(data):
        with send_lock:
            conn.sendall(data)

    send(b"INFO " + json.dumps(info).encode() + b"\r\n")

    def reader():
        buf = b""
        pings_after_sub = 0
        try:
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    return
                buf += chunk
                while b"\r\n" in buf:
                    line, buf = buf.split(b"\r\n", 1)
                    if line.startswith(b"PING"):
                        send(b"PONG\r\n")
                        if "sid" in sid_box:
                            pings_after_sub += 1
                            if pings_after_sub == 1:
                                subscribed.set()
                    elif line.startswith(b"SUB"):
                        parts = line.split()
                        sid_box["sid"] = parts[-1].decode()
        except OSError:
            return

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    subscribed.wait()
    time.sleep(0.5)
    payload = b"a" * args.size
    frame = f"MSG {args.subject} {sid_box['sid']} {args.size}\r\n".encode() + payload + b"\r\n"
    per_chunk = max(1, (1 << 20) // len(frame))
    chunk = frame * per_chunk
    full, rest = divmod(args.msgs, per_chunk)
    start = time.time()
    try:
        for _ in range(full):
            send(chunk)
        send(frame * rest)
    except OSError as e:
        print("send failed", e, flush=True)
    print(f"sent {args.msgs} msgs in {time.time() - start:.3f} s", flush=True)
    t.join()
    conn.close()


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", args.port))
srv.listen(1)
print(f"listening on {args.port}", flush=True)
for _ in range(args.loops):
    conn, _ = srv.accept()
    serve(conn)
srv.close()
