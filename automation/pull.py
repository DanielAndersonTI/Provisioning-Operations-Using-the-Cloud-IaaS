"""Bring back the evidence, results and logs a phase wrote on the VDI.

`run.py` already pulls after a phase, but a phase that ran to the end without
its output being copied leaves the data only on the guest. This script does the
download alone, without re-running anything.

Credentials come from the same environment variables `run.py` uses:

    VDI_HOST, VDI_PORT, VDI_USER, VDI_PASS

Usage:
    python automation/pull.py
"""

import sys

from run import PULL_DIRS, REPO, connect, download_tree

import posixpath


def main():
    client, user = connect()
    root = f"/home/{user}/atividade3"
    try:
        with client.open_sftp() as sftp:
            for name in PULL_DIRS:
                pulled = download_tree(sftp, posixpath.join(root, name), REPO / name)
                print(f"pulled {pulled} file(s) from {name}/")
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
