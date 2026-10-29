"""Drive the activity VM from the Windows host over SSH.

The activity has to be executed inside the professor's access VDI, so this
script does the typing: it uploads the remote phase scripts, runs one of them
through a PTY and streams the output to the console. Evidence the phase writes
inside the guest is pulled back into `evidencias/` and `results/`.

Credentials are read from the environment, never from this file:

    VDI_HOST, VDI_PORT, VDI_USER, VDI_PASS   access VDI (OpenSSH on VirtualBox NAT)
    CLOUD_USER, CLOUD_PASS                   LSD cloud account
    CLOUD_PROJECT                            defaults to `provisionamento`

Usage:
    python automation/run.py remote/00-bootstrap.sh
    python automation/run.py remote/10-recon.sh --pull
"""

import argparse
import os
import posixpath
import stat
import sys
from pathlib import Path

import paramiko


REPO = Path(__file__).resolve().parent.parent
AUTOMATION = REPO / "automation"
REMOTE_ROOT = "/home/{user}/atividade3"

# Directories the remote phases write to and this driver brings back.
PULL_DIRS = ["evidencias", "results", "logs"]

# Trees the remote phases consume and that must therefore live on the VDI too:
# the applications deployed to the VM in phase 5 and the load/monitor scripts
# used by the experiments.
PAYLOAD_DIRS = ["apps", "scripts"]


def env(name, default=None, required=False):
    value = os.environ.get(name, default)
    if required and not value:
        sys.exit(f"missing environment variable: {name}")
    return value


def connect():
    host = env("VDI_HOST", "127.0.0.1")
    port = int(env("VDI_PORT", "2222"))
    user = env("VDI_USER", "osboxes")
    password = env("VDI_PASS", required=True)

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        host,
        port=port,
        username=user,
        password=password,
        timeout=20,
        banner_timeout=30,
        auth_timeout=30,
        look_for_keys=False,
        allow_agent=False,
    )
    return client, user


def sftp_makedirs(sftp, path):
    parts = path.strip("/").split("/")
    current = ""
    for part in parts:
        current += "/" + part
        try:
            sftp.stat(current)
        except FileNotFoundError:
            sftp.mkdir(current)


def upload_tree(sftp, local_root, remote_root):
    for path in sorted(local_root.rglob("*")):
        if path.is_dir() or "__pycache__" in path.parts:
            continue
        relative = path.relative_to(local_root).as_posix()
        target = posixpath.join(remote_root, relative)
        sftp_makedirs(sftp, posixpath.dirname(target))
        sftp.put(str(path), target)
        sftp.chmod(target, 0o755)


def write_remote_file(sftp, path, content, mode=0o600):
    sftp_makedirs(sftp, posixpath.dirname(path))
    with sftp.file(path, "w") as handle:
        handle.write(content)
    sftp.chmod(path, mode)


def download_tree(sftp, remote_root, local_root):
    local_root.mkdir(parents=True, exist_ok=True)
    try:
        entries = list(sftp.listdir_attr(remote_root))
    except FileNotFoundError:
        return 0
    count = 0
    for entry in entries:
        remote = posixpath.join(remote_root, entry.filename)
        local = local_root / entry.filename
        if stat.S_ISDIR(entry.st_mode):
            count += download_tree(sftp, remote, local)
        else:
            local.parent.mkdir(parents=True, exist_ok=True)
            sftp.get(remote, str(local))
            count += 1
    return count


def emit(text):
    """Write guest output without dying on characters the console cannot encode.

    `hostnamectl` and friends decorate their output with Unicode icons. A Windows
    console is usually cp1252, where those characters raise UnicodeEncodeError
    and would abort the whole phase, so unrepresentable characters are replaced.
    """
    encoding = getattr(sys.stdout, "encoding", None) or "utf-8"
    buffer = getattr(sys.stdout, "buffer", None)
    if buffer is None:
        sys.stdout.write(text.encode(encoding, "replace").decode(encoding))
    else:
        buffer.write(text.encode(encoding, "replace"))
        buffer.flush()


def stream_command(client, command):
    transport = client.get_transport()
    channel = transport.open_session()
    channel.get_pty()
    channel.exec_command(command)
    while True:
        if channel.recv_ready():
            emit(channel.recv(4096).decode("utf-8", "replace"))
        if channel.recv_stderr_ready():
            emit(channel.recv_stderr(4096).decode("utf-8", "replace"))
        if channel.exit_status_ready() and not channel.recv_ready():
            break
    status = channel.recv_exit_status()
    # Drain whatever is still buffered after the exit status is available.
    while channel.recv_ready():
        emit(channel.recv(4096).decode("utf-8", "replace"))
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", help="path relative to automation/, e.g. remote/10-recon.sh")
    parser.add_argument("--pull", action="store_true", help="download evidence after the run")
    parser.add_argument("--no-upload", action="store_true", help="skip uploading automation/")
    args = parser.parse_args()

    client, user = connect()
    root = REMOTE_ROOT.format(user=user)
    sftp = client.open_sftp()

    if not args.no_upload:
        sftp_makedirs(sftp, root + "/automation")
        upload_tree(sftp, AUTOMATION / "remote", root + "/automation")
        for name in PAYLOAD_DIRS:
            source = REPO / name
            if source.is_dir():
                sftp_makedirs(sftp, f"{root}/{name}")
                upload_tree(sftp, source, f"{root}/{name}")
        sftp_makedirs(sftp, root + "/evidencias")
        sftp_makedirs(sftp, root + "/results")
        sftp_makedirs(sftp, root + "/logs")

    # Credentials for the cloud account, used by the phases that talk to
    # OpenStack. Kept on the guest with 0600 and out of the repository.
    cloud_env = "\n".join(
        [
            f"export CLOUD_USER='{env('CLOUD_USER', required=True)}'",
            f"export CLOUD_PASS='{env('CLOUD_PASS', required=True)}'",
            f"export CLOUD_PROJECT='{env('CLOUD_PROJECT', 'provisionamento')}'",
            f"export CLOUD_AUTH_URL='{env('CLOUD_AUTH_URL', 'https://cloud.lsd.ufcg.edu.br:5000/v3')}'",
            f"export CLOUD_DOMAIN='{env('CLOUD_DOMAIN', 'Default')}'",
            f"export CLOUD_PROJECT_DOMAIN='{env('CLOUD_PROJECT_DOMAIN', env('CLOUD_DOMAIN', 'Default'))}'",
            "export CLOUD_REGION='RegionOne'",
            f"export SUDO_PASS='{env('VDI_PASS', required=True)}'",
            "",
        ]
    )
    write_remote_file(sftp, f"/home/{user}/.atividade3/session.env", cloud_env)

    remote_script = posixpath.join(root, "automation", posixpath.basename(args.script))
    command = f"bash {remote_script}"
    print(f"\n===== {args.script} @ {user} =====\n", flush=True)
    status = stream_command(client, command)
    print(f"\n===== exit {status} =====\n", flush=True)

    if args.pull:
        for name in PULL_DIRS:
            pulled = download_tree(sftp, posixpath.join(root, name), REPO / name)
            print(f"pulled {pulled} file(s) from {name}/")

    sftp.close()
    client.close()
    return status


if __name__ == "__main__":
    raise SystemExit(main())
