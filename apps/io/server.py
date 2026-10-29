"""IO-bound backend application.

Every request writes a temporary file, flushes it to the storage device with
fsync, then reads it back, so the cost is dominated by disk latency rather than
by the processor or by memory.

    python apps/io/server.py --port 8000

Endpoints:
    GET /health       -> {"status": "ok", "profile": "io"}
    GET /work?size=N  -> write, sync and read back N KiB (default 1024, max 32768)

The fsync is what makes this profile meaningful: without it the kernel would
absorb the writes into the page cache and the request would measure memory speed
instead of storage speed.
"""

import argparse
import importlib.util
import sys
from pathlib import Path


PROFILE = "io"


def load_application_module():
    """Load apps/server.py by path.

    Loading by path instead of `import server` avoids a name collision: this
    file is itself named server.py, and the directory holding it sits on
    sys.path while it runs.
    """
    path = Path(__file__).resolve().parents[1] / "server.py"
    spec = importlib.util.spec_from_file_location("profile_server", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["profile_server"] = module
    spec.loader.exec_module(module)
    return module


def main():
    application = load_application_module()
    parser = argparse.ArgumentParser(description="IO-bound backend application.")
    parser.add_argument("--port", type=application.parse_port, default=8000)
    parser.add_argument(
        "--max-concurrency",
        type=application.parse_positive_int,
        default=None,
        help="simultaneously executing work units (default is profile-specific)",
    )
    args = parser.parse_args()
    application.serve(PROFILE, args.port, args.max_concurrency)


if __name__ == "__main__":
    main()
