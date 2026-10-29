"""Memory-bound backend application.

Every request allocates a buffer and touches one byte per 4-KiB page, so the
cost is dominated by allocating and faulting in memory rather than by the
processor or by disk.

    python apps/memory/server.py --port 8000

Endpoints:
    GET /health       -> {"status": "ok", "profile": "memory"}
    GET /work?size=N  -> allocate and touch N MiB (default 32, max 256)

The per-request ceiling is 256 MiB and the default admission limit is 4
concurrent work units, so the profile cannot allocate more than about 1 GiB in
total. Keep that product under the RAM of the smallest VM scenario you test,
otherwise the experiment measures the swap file instead of the profile.
"""

import argparse
import importlib.util
import sys
from pathlib import Path


PROFILE = "memory"


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
    parser = argparse.ArgumentParser(description="Memory-bound backend application.")
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
