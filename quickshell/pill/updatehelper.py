#!/usr/bin/env python3
# updatehelper.py — the ONLY part of the pill's updater that runs as root.
#
# Started by updatebridge.py's orchestrator through `pkexec` (the normal polkit
# password dialog). It is deliberately a dumb relay: it runs pacman inside a
# pseudo-terminal and mirrors it into plain files in the run directory, so the
# unprivileged side can parse progress and put pacman's questions in front of
# the user. It never decides anything and never takes a command line from its
# caller — only a fixed `mode`:
#
#   updatehelper.py RUNDIR UID full       pacman -Syu
#   updatehelper.py RUNDIR UID keyring    pacman -Sy --needed archlinux-keyring,
#                                         then pacman -Su (stale-keyring safe)
#   updatehelper.py RUNDIR UID fake SCRIPT   test seam: run SCRIPT instead of
#                                         pacman. REFUSED when running as root.
#
# Files in RUNDIR (all chowned to UID so the user's tools can open them):
#   pacman.log   every complete line pacman printed (plain text, no colour codes)
#   pending      the current unterminated line — i.e. a question pacman is
#                waiting on ("… [Y/n] "). Removed when the line completes.
#   answer       written by the user side; its content (validated: y/n/number)
#                is typed into pacman, then the file is deleted.
#   stop         written by the user side; pacman gets SIGINT (then SIGTERM).
#   exit         pacman's exit status, written last.
import fcntl
import os
import pty
import re
import select
import signal
import struct
import sys
import termios
import time

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][A-Za-z0-9]")
ANSWER_OK = re.compile(r"^[yYnN0-9 ,^-]{0,24}$")
PACMAN = "/usr/bin/pacman"
COMMON = ["--noprogressbar", "--color", "never"]


def die(msg, code=2):
    sys.stderr.write("updatehelper: %s\n" % msg)
    sys.exit(code)


class Out:
    """Run-directory files, created without following symlinks, owned by uid."""

    def __init__(self, rundir, uid):
        self.dir = rundir
        self.uid = uid
        self.log = self._open("pacman.log", os.O_APPEND)

    def _open(self, name, extra=0):
        path = os.path.join(self.dir, name)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | extra, 0o644)
        self._own(fd)
        return fd

    def _own(self, fd):
        if os.geteuid() == 0:
            try:
                os.fchown(fd, self.uid, -1)
            except OSError:
                pass

    def line(self, text):
        os.write(self.log, (text + "\n").encode("utf-8", "replace"))

    def put(self, name, text):
        tmp = os.path.join(self.dir, "." + name + ".tmp")
        try:
            os.unlink(tmp)
        except OSError:
            pass
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        self._own(fd)
        os.write(fd, text.encode("utf-8", "replace"))
        os.close(fd)
        os.rename(tmp, os.path.join(self.dir, name))

    def drop(self, name):
        try:
            os.unlink(os.path.join(self.dir, name))
        except OSError:
            pass

    def take(self, name):
        """Read + delete a small user-written control file (None when absent)."""
        path = os.path.join(self.dir, name)
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        except OSError:
            return None
        try:
            data = os.read(fd, 64).decode("utf-8", "replace")
        finally:
            os.close(fd)
            self.drop(name)
        return data


def relay(argv, env, out):
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execve(argv[0], argv, env)
        finally:
            os._exit(127)
    try:  # a wide terminal so pacman never wraps its package list oddly
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
    except OSError:
        pass
    buf = ""
    shown = None
    stops = 0
    alive = True
    while alive:
        try:
            ready, _, _ = select.select([fd], [], [], 0.2)
        except InterruptedError:
            continue
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                chunk = b""
            if not chunk:
                alive = False
            else:
                buf += ANSI.sub("", chunk.decode("utf-8", "replace"))
                # \r without \n is a redraw of the same line — keep the last one
                parts = buf.split("\n")
                buf = parts.pop()
                for p in parts:
                    out.line(p.rstrip("\r").split("\r")[-1])
        partial = buf.split("\r")[-1]
        if partial != shown:
            shown = partial
            if partial.strip():
                out.put("pending", partial)
            else:
                out.drop("pending")
        ans = out.take("answer")
        if ans is not None:
            ans = ans.strip()
            if ANSWER_OK.match(ans):
                os.write(fd, (ans + "\n").encode())
        if out.take("stop") is not None:
            stops += 1
            try:
                os.kill(pid, signal.SIGINT if stops == 1 else signal.SIGTERM)
            except OSError:
                pass
    if buf.strip():
        out.line(buf.rstrip("\r").split("\r")[-1])
    out.drop("pending")
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status)


def main():
    a = sys.argv[1:]
    if len(a) < 3:
        die("usage: updatehelper.py RUNDIR UID full|keyring|fake [SCRIPT]")
    rundir, mode = a[0], a[2]
    try:
        uid = int(a[1])
    except ValueError:
        die("bad uid")
    if not os.path.isabs(rundir) or os.path.islink(rundir) or not os.path.isdir(rundir):
        die("run directory must be an existing absolute directory")
    if os.stat(rundir).st_uid != uid:
        die("run directory is not owned by the requesting user")

    env = {
        "PATH": "/usr/bin:/usr/sbin:/bin:/sbin",
        "LC_ALL": "C",
        "LANG": "C",
        "TERM": "dumb",
        "HOME": "/root" if os.geteuid() == 0 else os.path.expanduser("~"),
    }
    if mode == "full":
        cmds = [[PACMAN, "-Syu"] + COMMON]
    elif mode == "keyring":
        cmds = [
            [PACMAN, "-Sy", "--needed", "--noconfirm", "archlinux-keyring"] + COMMON,
            [PACMAN, "-Su"] + COMMON,
        ]
    elif mode == "fake":
        if os.geteuid() == 0:
            die("fake mode is refused as root")
        if len(a) < 4 or not os.path.isfile(a[3]):
            die("fake mode needs a script")
        cmds = [[sys.executable, a[3]]]
        env["PYTHONUNBUFFERED"] = "1"
    else:
        die("unknown mode")

    out = Out(rundir, uid)
    out.drop("exit")
    rc = 0
    for argv in cmds:
        rc = relay(argv, env, out)
        if rc != 0:
            break
    out.put("exit", str(rc))
    time.sleep(0.05)
    sys.exit(0 if rc == 0 else 1)


if __name__ == "__main__":
    main()
