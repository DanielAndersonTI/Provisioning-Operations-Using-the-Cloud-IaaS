"""CPU-bound backend application.

Each request hashes a fixed 1 MiB block a number of times. The work stays on the
processor and touches neither disk nor a meaningful amount of memory.

    python apps/cpu/server.py --port 8000

Endpoints:
    GET /health       -> {"status": "ok", "profile": "cpu"}
    GET /work?size=N  -> N hashes of a 1 MiB block (default 10, max 300)

The 1 MiB block is deliberate, not incidental. CPython releases the GIL for
hashlib inputs of 2048 bytes or more, so a large buffer lets concurrent requests
be served on several cores at once. That is what makes this profile able to
respond to the number of vCPUs the VM is provisioned with; a chain of small
digests would stay GIL-bound and no amount of extra CPU would change anything.

Rough cost on a modest machine: about 10-15 ms per iteration, so the default
request takes on the order of 100-150 ms. Measure it on the target VM rather
than assuming, and pick the size used in the experiments from that measurement.
"""

import argparse
import importlib.util
import sys
from pathlib import Path


PROFILE = "cpu"


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
    parser = argparse.ArgumentParser(description="CPU-bound backend application.")
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
