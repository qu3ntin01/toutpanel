from __future__ import annotations

import os
import platform as _platform
import shutil
import subprocess
from dataclasses import dataclass
from typing import Callable, Iterable, Optional


@dataclass
class CommandResult:
    code: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.code == 0

    @property
    def output(self) -> str:
        return (self.stdout + ("\n" + self.stderr if self.stderr else "")).strip()


class BasePlatform:
    name = "base"

    # ------------------------------------------------------------------ exécution
    def run(self, cmd, timeout: int = 600, shell: bool = False, cwd: Optional[str] = None,
            env: Optional[dict] = None, input_text: Optional[str] = None) -> CommandResult:
        """Exécute une commande et capture sa sortie via des fichiers temporaires (et non des pipes) :
        un démon lancé par la commande (ex: `service dovecot restart`) qui hérite des descripteurs
        ne bloque ainsi jamais l'appel jusqu'au timeout."""
        import tempfile

        full_env = dict(os.environ)
        if env:
            full_env.update(env)
        try:
            with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
                p = subprocess.Popen(cmd, shell=shell, cwd=cwd, env=full_env, stdout=out, stderr=err,
                                     stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL)
                try:
                    if input_text is not None:
                        p.stdin.write(input_text.encode("utf-8", errors="replace"))
                        p.stdin.close()
                    code = p.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    p.kill()
                    p.wait()
                    return CommandResult(124, "", f"timeout après {timeout}s")
                out.seek(0)
                err.seek(0)
                return CommandResult(code, out.read().decode("utf-8", errors="replace"), err.read().decode("utf-8", errors="replace"))
        except FileNotFoundError as e:
            return CommandResult(127, "", str(e))
        except Exception as e:  # pragma: no cover
            return CommandResult(1, "", str(e))

    def run_shell(self, command: str, timeout: int = 600, cwd: Optional[str] = None) -> CommandResult:
        return self.run(command, timeout=timeout, shell=True, cwd=cwd)

    def stream(self, cmd, on_line: Callable[[str], None], shell: bool = False, cwd: Optional[str] = None,
               env: Optional[dict] = None, timeout: int = 3600) -> int:
        """Exécute une commande et transmet chaque ligne de sortie à on_line. Retourne le code de sortie.
        Un délai maximal (1 h par défaut) tue la commande : un téléchargement bloqué ne laisse pas une tâche pendante."""
        import threading

        full_env = dict(os.environ)
        full_env.update(env or {})
        try:
            p = subprocess.Popen(cmd, shell=shell, cwd=cwd, env=full_env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, text=True, errors="replace", bufsize=1)
        except FileNotFoundError as e:
            on_line(f"Erreur: {e}")
            return 127
        timer = threading.Timer(timeout, lambda: (on_line(f"Délai dépassé ({timeout} s) : commande interrompue"), p.kill()))
        timer.daemon = True
        timer.start()
        try:
            assert p.stdout is not None
            for line in p.stdout:
                on_line(line.rstrip("\n"))
            return p.wait()
        finally:
            timer.cancel()

    def which(self, name: str) -> Optional[str]:
        return shutil.which(name)

    def shell_executable(self) -> list[str]:
        return ["/bin/bash"] if os.path.exists("/bin/bash") else ["/bin/sh"]

    # ------------------------------------------------------------------ infos
    def os_info(self) -> dict:
        return {
            "system": _platform.system(), "release": _platform.release(), "version": _platform.version(),
            "machine": _platform.machine(), "hostname": _platform.node(), "pretty": _platform.platform(),
        }

    def is_admin(self) -> bool:
        return False

    # ------------------------------------------------------------------ services
    def service_status(self, name: str) -> str:
        raise NotImplementedError

    def service_action(self, name: str, action: str) -> CommandResult:
        raise NotImplementedError

    def list_services(self) -> list[dict]:
        return []

    # ------------------------------------------------------------------ paquets
    def package_manager(self) -> str:
        return ""

    def install_packages(self, packages: Iterable[str], on_line: Callable[[str], None]) -> int:
        raise NotImplementedError

    def remove_packages(self, packages: Iterable[str], on_line: Callable[[str], None]) -> int:
        raise NotImplementedError

    def package_installed(self, package: str) -> bool:
        return False

    def package_available(self, package: str) -> bool:
        """Le paquet existe-t-il dans les dépôts ? (True par défaut si indéterminable)"""
        return True

    # ------------------------------------------------------------------ pare-feu
    def firewall_backend(self) -> str:
        return ""

    def firewall_status(self) -> dict:
        return {"backend": "", "enabled": False}

    def firewall_enable(self, enable: bool) -> CommandResult:
        return CommandResult(1, "", "non supporté")

    def firewall_add(self, port: str, protocol: str, action: str, source: str, remark: str) -> CommandResult:
        return CommandResult(1, "", "non supporté")

    def firewall_remove(self, port: str, protocol: str, action: str, source: str, remark: str) -> CommandResult:
        return CommandResult(1, "", "non supporté")

    # ------------------------------------------------------------------ divers
    def web_user(self) -> str:
        return ""

    def chown_web(self, path: str) -> None:
        pass

    def reboot(self) -> CommandResult:
        return CommandResult(1, "", "non supporté")
