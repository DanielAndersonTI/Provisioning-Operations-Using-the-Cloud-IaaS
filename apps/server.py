"""Backend web applications for the demand, provisioning and performance study.

This module implements the three computational profiles required by the
assignment behind a single, small HTTP surface:

    GET /health        -> identifies the running profile
    GET /work?size=N   -> performs one bounded unit of work for that profile

Each profile has its own safe size range, and the number of work units that may
execute simultaneously is bounded. Requests that arrive while every slot is busy
are rejected immediately with HTTP 503 instead of queueing without limit, so a
load experiment cannot drive the machine into uncontrolled resource use.

For the study, prefer the per-profile entry points, which pin the profile:

    python apps/cpu/server.py    --port 8000
    python apps/memory/server.py --port 8000
    python apps/io/server.py     --port 8000

This module also runs directly, which is convenient for quick checks:

    python apps/server.py --profile cpu --port 8000
"""

import argparse
import hashlib
import json
import os
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


PROFILES = ("cpu", "memory", "io")

# `size` is profile-specific: CPU block iterations, memory MiB, IO KiB.
DEFAULT_SIZE = {"cpu": 10, "memory": 32, "io": 1024}
MAX_SIZE = {"cpu": 300, "memory": 256, "io": 32_768}

# Safety ceiling on simultaneously executing work units. Unlike the size limits,
# this bounds the *aggregate* footprint of the process. The values are chosen so
# that the worst case stays inside the RAM of the smallest VM scenario used in
# the experiments: the memory profile can allocate up to 256 MiB per request, so
# 4 slots cap it at roughly 1 GiB. The CPU and IO profiles hold no comparable
# per-request buffer, so they can admit more concurrency; the cap there exists
# only to stop a runaway client from spawning threads without limit.
DEFAULT_MAX_CONCURRENCY = {"cpu": 32, "memory": 4, "io": 16}


CPU_BLOCK_SIZE = 1024 * 1024
CPU_SEED = b"demanda-desempenho"


def _build_cpu_block():
    repeats = CPU_BLOCK_SIZE // len(CPU_SEED) + 1
    return bytearray((CPU_SEED * repeats)[:CPU_BLOCK_SIZE])


def compute_cpu(iterations):
    """CPU-bound work: repeated SHA-256 over a fixed 1 MiB block, CPU only.

    The block is large on purpose. CPython releases the GIL for hashlib inputs
    of 2048 bytes or more, so hashing a big buffer lets several worker threads
    occupy several cores at once. A chain of small digests would stay inside the
    GIL and the application could not gain anything at all from extra vCPUs,
    which is precisely the relationship these experiments have to measure.

    The previous digest is written back into the first 32 bytes of the block, so
    each iteration still depends on the one before it and the request remains
    fully CPU-bound and deterministic for a given size.
    """
    block = _build_cpu_block()
    digest = b""
    for _ in range(iterations):
        digest = hashlib.sha256(block).digest()
        block[0:32] = digest
    return {"sha256": digest.hex(), "iterations": iterations}


def compute_memory(mib):
    """Memory-bound work: allocate, touch every 4-KiB page, then sample."""
    buf = bytearray(mib * 1024 * 1024)
    for index in range(0, len(buf), 4096):
        buf[index] = (index // 4096) % 251
    checksum = sum(buf[::4096])
    return {"allocated_mib": mib, "checksum": checksum}


def compute_io(kib):
    """IO-bound work: write, flush to disk, then read back a temporary file."""
    payload = b"X" * 65536
    with tempfile.TemporaryFile() as file:
        remaining = kib * 1024
        while remaining:
            chunk = payload[: min(len(payload), remaining)]
            file.write(chunk)
            remaining -= len(chunk)
        file.flush()
        os.fsync(file.fileno())
        file.seek(0)
        amount = 0
        while True:
            chunk = file.read(65536)
            if not chunk:
                break
            amount += len(chunk)
    return {"bytes_read": amount, "bytes_written": kib * 1024}


class WorkRequestHandler(BaseHTTPRequestHandler):
    """Serves /health and /work for one profile.

    `profile` and `work_slots` are injected per server instance by `serve`, so
    every instance owns its own admission limit.
    """

    profile = "cpu"
    work_slots = None

    def do_GET(self):
        request = urlparse(self.path)

        if request.path == "/health":
            self._respond(200, {"status": "ok", "profile": self.profile})
            return

        if request.path != "/work":
            self._respond(404, {"error": "Use /health or /work?size=N"})
            return

        try:
            size = self._parse_size(request.query)
        except ValueError:
            self._respond(
                400,
                {
                    "error": (
                        "size must be a single decimal integer between 1 and "
                        f"{MAX_SIZE[self.profile]}"
                    )
                },
            )
            return

        if not self.work_slots.acquire(blocking=False):
            self._respond(503, {"error": "server busy: all work slots are in use"})
            return

        try:
            start = time.perf_counter()
            try:
                result = self._compute(size)
            except OSError:
                # Do not echo the exception text: it can disclose server paths.
                self._respond(500, {"error": "work failed: storage error"})
                return
            elapsed = time.perf_counter() - start
        finally:
            self.work_slots.release()

        self._respond(
            200,
            {
                "profile": self.profile,
                "duration_seconds": round(elapsed, 6),
                "result": result,
            },
        )

    def _parse_size(self, query):
        values = parse_qs(query, keep_blank_values=True).get("size")
        if values is None:
            return DEFAULT_SIZE[self.profile]
        if len(values) != 1 or not values[0].isascii() or not values[0].isdecimal():
            raise ValueError("size must be a single decimal integer")

        size = int(values[0])
        if not 1 <= size <= MAX_SIZE[self.profile]:
            raise ValueError("size is outside the supported range")
        return size

    def _compute(self, size):
        if self.profile == "cpu":
            return compute_cpu(size)
        if self.profile == "memory":
            return compute_memory(size)
        return compute_io(size)

    def _respond(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        """Silence the per-request access log.

        The experiments generate thousands of requests; writing a line per
        request would add IO to the very profiles under measurement.
        """


def parse_port(value):
    try:
        port = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("port must be an integer") from error
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("port must be between 1 and 65535")
    return port


def parse_positive_int(value):
    try:
        number = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be an integer") from error
    if number < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return number


def serve(profile, port, max_concurrency=None):
    """Run the application for `profile` on `port` until interrupted."""
    if profile not in PROFILES:
        raise ValueError(f"unknown profile: {profile!r}")
    if max_concurrency is None:
        max_concurrency = DEFAULT_MAX_CONCURRENCY[profile]

    handler = type(
        f"{profile.capitalize()}RequestHandler",
        (WorkRequestHandler,),
        {
            "profile": profile,
            "work_slots": threading.BoundedSemaphore(max_concurrency),
        },
    )

    server = ThreadingHTTPServer(("0.0.0.0", port), handler)
    # Let Ctrl+C stop the process even with requests still in flight.
    server.daemon_threads = True

    print(
        f"{profile} application listening on port {port} "
        f"(max {max_concurrency} concurrent work units)",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(
        description="Run one of the three backend applications."
    )
    parser.add_argument("--profile", choices=PROFILES, required=True)
    parser.add_argument("--port", type=parse_port, default=8000)
    parser.add_argument(
        "--max-concurrency",
        type=parse_positive_int,
        default=None,
        help="simultaneously executing work units (default is profile-specific)",
    )
    args = parser.parse_args()
    serve(args.profile, args.port, args.max_concurrency)


if __name__ == "__main__":
    main()
