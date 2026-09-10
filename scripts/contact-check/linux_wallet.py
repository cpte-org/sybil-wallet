#!/usr/bin/env python3
"""Launch a disposable Linux Vizor profile with its own real Secret Service.

Usage: python3 linux_wallet.py --bundle /absolute/bundle --state-dir /tmp/alice
Add --probe-only to check the private service without launching Vizor.

State persists until its owner removes it. Network access is shared for testnet;
this isolates trusted test applications from host wallet files and the host
filesystem D-Bus socket, and is not a sandbox for hostile application code.
No host accessibility bus is exposed; use screenshots and coordinate input.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time


MARKER_NAME = ".vizor-contact-check-state"
MARKER = b"vizor-contact-check-linux-state-v1\n"
BUS_ADDRESS = "unix:path=/state/runtime/bus"
INNER_TOKEN = "vizor-contact-check-linux-v1"


def checked_path(value: str, *, exists: bool) -> Path:
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("Paths must be absolute and must not contain '..'.")
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError("Symlinks are not accepted in bundle or state paths.")
    if exists and not path.is_dir():
        raise ValueError("The bundle must be an existing directory.")
    return path


def private_directory(path: Path) -> None:
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("State directories must be real directories owned by this user.")
    if stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("Existing state directories must have mode 0700.")


def open_private(path: Path, flags: int) -> int:
    fd = os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    info = os.fstat(fd)
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600):
        os.close(fd)
        raise ValueError("State files must be private regular files owned by this user.")
    return fd


def prepare_state(path: Path) -> int:
    # Do not adopt an arbitrary directory merely because the caller named it.
    if path.exists():
        if not path.is_dir():
            raise ValueError("The state path must be a directory.")
        entries = list(path.iterdir())
        if entries and not (path / MARKER_NAME).exists():
            raise ValueError("Refusing a nonempty directory without the launcher marker.")
        if not entries:
            if path.stat().st_uid != os.getuid():
                raise ValueError("The empty state directory must belong to this user.")
            path.chmod(0o700)
    private_directory(path)
    marker = path / MARKER_NAME
    if not marker.exists():
        with os.fdopen(open_private(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL), "wb") as stream:
            stream.write(MARKER)
            stream.flush()
            os.fsync(stream.fileno())
    with os.fdopen(open_private(marker, os.O_RDONLY), "rb") as stream:
        if stream.read(len(MARKER) + 1) != MARKER:
            raise ValueError("The state directory has an unrecognized launcher marker.")
    lock = open_private(path / ".launcher.lock", os.O_RDWR | os.O_CREAT)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for name in ("data", "config", "cache", "state", "tmp", "runtime", "logs"):
            private_directory(path / name)
        return lock
    except BaseException:
        os.close(lock)
        raise


def wayland_socket() -> Path:
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if not display:
        raise ValueError("WAYLAND_DISPLAY is required for a GUI launch.")
    path = Path(display)
    if not path.is_absolute():
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        if not runtime or not Path(runtime).is_absolute() or len(path.parts) != 1:
            raise ValueError("Cannot resolve the host Wayland socket safely.")
        path = Path(runtime) / path
    if path.is_symlink() or not stat.S_ISSOCK(path.stat().st_mode):
        raise ValueError("The supplied Wayland display is not a real socket.")
    return path


def stop(process: subprocess.Popen[bytes]) -> None:
    # Each explicitly started child has its own process group. The PID namespace
    # also contains any service-activated or daemonized descendants.
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=4)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=4)


def interrupted(signum: int, _frame: object) -> None:
    raise InterruptedError(f"Stopped by signal {signum}.")


def outer(args: argparse.Namespace) -> int:
    bundle = checked_path(args.bundle, exists=True)
    state = checked_path(args.state_dir, exists=False)
    if not (bundle / "vizor").is_file() or not os.access(bundle / "vizor", os.X_OK):
        raise ValueError("The bundle must contain an executable named 'vizor'.")
    for executable in ("/usr/bin/bwrap", "/usr/bin/python3", "/usr/bin/dbus-daemon",
                       "/usr/bin/ksecretd", "/usr/bin/busctl"):
        if not os.access(executable, os.X_OK):
            raise ValueError(f"Required installed executable is missing: {executable}")
    display = None if args.probe_only else wayland_socket()
    lock = prepare_state(state)
    try:
        command = [
            "/usr/bin/bwrap", "--die-with-parent", "--new-session",
            "--unshare-user", "--unshare-pid", "--unshare-ipc", "--unshare-uts",
            "--cap-drop", "ALL", "--clearenv",
            "--ro-bind", "/usr", "/usr", "--ro-bind", "/etc", "/etc",
            "--proc", "/proc", "--dev", "/dev",
            "--tmpfs", "/home", "--tmpfs", "/root", "--tmpfs", "/tmp",
            "--tmpfs", "/run", "--dir", "/run/user",
            "--ro-bind", str(bundle), "/app", "--bind", str(state), "/state",
            "--ro-bind", str(Path(__file__).resolve()), "/launcher.py",
            "--chdir", "/app",
        ]
        # Support both merged-/usr and traditional system layouts.
        for name in ("bin", "sbin", "lib", "lib64"):
            source = Path("/") / name
            if source.is_symlink():
                command.extend(["--symlink", os.readlink(source), str(source)])
            elif source.is_dir():
                command.extend(["--ro-bind", str(source), str(source)])
        # /etc/resolv.conf may point into the otherwise hidden host /run.
        resolver = Path("/etc/resolv.conf").resolve(strict=True)
        if not resolver.is_relative_to("/etc") and not resolver.is_relative_to("/usr"):
            if not resolver.is_relative_to("/run"):
                raise ValueError("Unexpected resolver target outside system directories.")
            command.extend(["--ro-bind", str(resolver), str(resolver)])
        environment = {
            "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8",
            "CONTACT_CHECK_INSIDE": INNER_TOKEN,
            "DBUS_SESSION_BUS_ADDRESS": BUS_ADDRESS,
            "XDG_DATA_HOME": "/state/data", "XDG_CONFIG_HOME": "/state/config",
            "XDG_CACHE_HOME": "/state/cache", "XDG_STATE_HOME": "/state/state",
            "XDG_RUNTIME_DIR": "/state/runtime", "TMPDIR": "/state/tmp",
            "GDK_BACKEND": "wayland", "QT_QPA_PLATFORM": "wayland",
            "LIBGL_ALWAYS_SOFTWARE": "1", "NO_AT_BRIDGE": "1",
            # Debug plugins can retain build-tree RUNPATH entries. Resolve all
            # native dependencies from the read-only installed bundle instead.
            "LD_LIBRARY_PATH": "/app/lib",
        }
        # Preserve the real HOME string; its host filesystem contents are masked.
        if "HOME" in os.environ:
            environment["HOME"] = os.environ["HOME"]
        if display is not None:
            command.extend(["--ro-bind", str(display), "/contact-wayland"])
            environment["WAYLAND_DISPLAY"] = "/contact-wayland"
        else:
            environment["QT_QPA_PLATFORM"] = "offscreen"
        for key, value in environment.items():
            command.extend(["--setenv", key, value])
        command.extend(["/usr/bin/python3", "/launcher.py", "--inner"])
        if args.probe_only:
            command.append("--probe-only")
        log_path = state / "logs" / f"launcher-{time.time_ns()}-{os.getpid()}.log"
        with os.fdopen(open_private(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL), "wb") as log:
            print(f"Private launcher log: {log_path}", flush=True)
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                       stdin=subprocess.DEVNULL, start_new_session=True)
            try:
                result = process.wait()
            finally:
                stop(process)
        print(f"Private {'probe' if args.probe_only else 'wallet'} exited with status {result}.")
        return result
    finally:
        os.close(lock)


def service_owned() -> bool:
    try:
        result = subprocess.run([
            "/usr/bin/busctl", f"--address={BUS_ADDRESS}", "--timeout=1",
            "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "NameHasOwner", "s", "org.freedesktop.secrets",
        ], capture_output=True, timeout=2, check=False)
        return result.returncode == 0 and result.stdout.strip() == b"b true"
    except subprocess.TimeoutExpired:
        return False


def inner(args: argparse.Namespace) -> int:
    if (os.environ.get("CONTACT_CHECK_INSIDE") != INNER_TOKEN
            or os.environ.get("DBUS_SESSION_BUS_ADDRESS") != BUS_ADDRESS
            or Path(__file__) != Path("/launcher.py")
            or Path("/state", MARKER_NAME).read_bytes() != MARKER):
        raise ValueError("The internal stage must only run inside the launcher namespace.")
    os.umask(0o077)
    socket = Path("/state/runtime/bus")
    if socket.exists() or socket.is_symlink():
        if not stat.S_ISSOCK(socket.lstat().st_mode):
            raise ValueError("Refusing to replace a non-socket runtime/bus entry.")
        socket.unlink()  # Only the exact stale private socket, under the outer lock.
    children: list[subprocess.Popen[bytes]] = []
    with contextlib.ExitStack() as stack:
        def spawn(name: str, command: list[str]) -> subprocess.Popen[bytes]:
            log_path = Path("/state/logs") / f"{name}-{time.time_ns()}.log"
            log = stack.enter_context(os.fdopen(
                open_private(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL), "wb"))
            child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, start_new_session=True)
            children.append(child)
            return child

        try:
            bus = spawn("dbus", ["/usr/bin/dbus-daemon", "--session", "--nofork",
                                 f"--address={BUS_ADDRESS}", "--nopidfile"])
            deadline = time.monotonic() + 10
            while not socket.exists():
                if bus.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("The private D-Bus daemon did not become ready.")
                time.sleep(0.1)
            spawn("secrets", ["/usr/bin/ksecretd"])
            deadline = time.monotonic() + 25
            while not service_owned():
                if bus.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("Private org.freedesktop.secrets did not acquire its name; inspect owned logs.")
                time.sleep(0.2)
            print("Verified private org.freedesktop.secrets ownership.", flush=True)
            if args.probe_only:
                return 0
            wallet = spawn("wallet", ["/app/vizor"])
            while wallet.poll() is None:
                if bus.poll() is not None or not service_owned():
                    raise RuntimeError("The private Secret Service stopped while the wallet was running.")
                time.sleep(1)
            return wallet.returncode
        finally:
            for child in reversed(children):
                # Continue cleaning up the bus even if another child stalls;
                # namespace teardown also terminates remaining descendants.
                with contextlib.suppress(subprocess.TimeoutExpired):
                    stop(child)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", help="Absolute Linux bundle containing vizor")
    parser.add_argument("--state-dir", help="Absolute fresh or launcher-marked actor directory")
    parser.add_argument("--probe-only", action="store_true")
    parser.add_argument("--inner", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.inner and (not args.bundle or not args.state_dir):
        parser.error("--bundle and --state-dir are required")
    if args.inner and (args.bundle or args.state_dir):
        parser.error("The internal stage does not accept host paths")
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        return inner(args) if args.inner else outer(args)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Contact-check launcher: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
