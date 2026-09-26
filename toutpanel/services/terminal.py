"""Terminal web : pseudo-terminal (Linux) ou pywinpty / pipes (Windows)."""
from __future__ import annotations

import os
import threading
from typing import Callable

from toutpanel import config
from toutpanel.platform import get_platform


class TerminalSession:
    def __init__(self, on_output: Callable[[bytes], None], cols: int = 120, rows: int = 32):
        self.on_output = on_output
        self.cols, self.rows = cols, rows
        self.alive = False
        self._pid = None
        self._fd = None
        self._proc = None
        self._pty = None

    def start(self) -> None:
        shell = get_platform().shell_executable()
        cwd = str(config.WWW_ROOT if config.WWW_ROOT.exists() else config.HOME)
        if config.IS_WINDOWS:
            self._start_windows(shell, cwd)
        else:
            self._start_posix(shell, cwd)
        self.alive = True

    # ---------------------------------------------------------------- POSIX
    def _start_posix(self, shell: list[str], cwd: str) -> None:
        import fcntl
        import pty
        import struct
        import termios

        pid, fd = pty.fork()
        if pid == 0:  # enfant
            try:
                os.chdir(cwd)
                env = dict(os.environ, TERM="xterm-256color", LANG=os.environ.get("LANG", "C.UTF-8"))
                os.execvpe(shell[0], shell, env)
            except BaseException:  # noqa: BLE001 — jamais laisser l'enfant continuer à exécuter le serveur
                os._exit(127)
        self._pid, self._fd = pid, fd
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", self.rows, self.cols, 0, 0))

        def _reader():
            while True:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                self.on_output(data)
            self.alive = False

        threading.Thread(target=_reader, daemon=True).start()

    # ---------------------------------------------------------------- Windows
    def _start_windows(self, shell: list[str], cwd: str) -> None:
        try:
            import winpty  # type: ignore

            self._pty = winpty.PtyProcess.spawn(shell, cwd=cwd, dimensions=(self.rows, self.cols))

            def _reader():
                while self._pty and self._pty.isalive():
                    try:
                        data = self._pty.read(4096)
                    except (EOFError, OSError):
                        break
                    if data:
                        self.on_output(data.encode("utf-8", errors="replace"))
                self.alive = False

            threading.Thread(target=_reader, daemon=True).start()
        except ImportError:
            import subprocess

            self._proc = subprocess.Popen(shell, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                          stderr=subprocess.STDOUT, bufsize=0)

            def _reader():
                assert self._proc and self._proc.stdout
                while True:
                    data = self._proc.stdout.read1(4096) if hasattr(self._proc.stdout, "read1") else self._proc.stdout.read(1)
                    if not data:
                        break
                    self.on_output(data.replace(b"\n", b"\r\n"))
                self.alive = False

            threading.Thread(target=_reader, daemon=True).start()
            self.on_output(b"[pywinpty absent : mode simplifie, pas d'applications interactives]\r\n")

    # ---------------------------------------------------------------- I/O
    def write(self, data: bytes) -> None:
        if self._fd is not None:
            os.write(self._fd, data)
        elif self._pty is not None:
            self._pty.write(data.decode("utf-8", errors="replace"))
        elif self._proc and self._proc.stdin:
            self._proc.stdin.write(data.replace(b"\r", b"\r\n") if data == b"\r" else data)
            self._proc.stdin.flush()

    def resize(self, cols: int, rows: int) -> None:
        self.cols, self.rows = cols, rows
        if self._fd is not None:
            import fcntl
            import struct
            import termios

            try:
                fcntl.ioctl(self._fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
            except OSError:
                pass
        elif self._pty is not None:
            try:
                self._pty.setwinsize(rows, cols)
            except Exception:
                pass

    def close(self) -> None:
        self.alive = False
        if self._fd is not None:
            try:
                os.close(self._fd)
            except OSError:
                pass
            if self._pid:
                try:
                    os.kill(self._pid, 9)
                    os.waitpid(self._pid, 0)
                except (OSError, ChildProcessError):
                    pass
        if self._pty is not None:
            try:
                self._pty.terminate(force=True)
            except Exception:
                pass
        if self._proc is not None:
            try:
                self._proc.kill()
            except Exception:
                pass
