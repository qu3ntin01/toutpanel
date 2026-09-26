from __future__ import annotations

import ctypes
import os
import shutil
from typing import Callable, Iterable, Optional

from toutpanel.platform.base import BasePlatform, CommandResult


class WindowsPlatform(BasePlatform):
    name = "windows"

    def is_admin(self) -> bool:
        try:
            return bool(ctypes.windll.shell32.IsUserAnAdmin())  # type: ignore[attr-defined]
        except Exception:
            return False

    def shell_executable(self) -> list[str]:
        ps = shutil.which("powershell") or shutil.which("pwsh")
        return [ps, "-NoLogo"] if ps else [os.environ.get("COMSPEC", "cmd.exe")]

    def run_shell(self, command: str, timeout: int = 600, cwd: Optional[str] = None) -> CommandResult:
        ps = shutil.which("powershell")
        if ps:
            return self.run([ps, "-NoProfile", "-NonInteractive", "-Command", command], timeout=timeout, cwd=cwd)
        return self.run(command, timeout=timeout, shell=True, cwd=cwd)

    # ------------------------------------------------------------------ services
    def service_status(self, name: str) -> str:
        r = self.run(["sc", "query", name], timeout=15)
        if not r.ok:
            return "unknown"
        if "RUNNING" in r.stdout:
            return "running"
        if "STOPPED" in r.stdout:
            return "stopped"
        return "unknown"

    def service_action(self, name: str, action: str) -> CommandResult:
        if action == "start":
            return self.run(["sc", "start", name], timeout=60)
        if action == "stop":
            return self.run(["sc", "stop", name], timeout=60)
        if action in ("restart", "reload"):
            self.run(["sc", "stop", name], timeout=60)
            import time

            time.sleep(2)
            return self.run(["sc", "start", name], timeout=60)
        if action == "enable":
            return self.run(["sc", "config", name, "start=", "auto"], timeout=30)
        if action == "disable":
            return self.run(["sc", "config", name, "start=", "disabled"], timeout=30)
        return CommandResult(1, "", "action invalide")

    def list_services(self) -> list[dict]:
        r = self.run_shell("Get-Service | Select-Object Name,Status,DisplayName | ConvertTo-Json -Compress", timeout=30)
        out: list[dict] = []
        if r.ok and r.stdout.strip():
            import json

            try:
                data = json.loads(r.stdout)
                if isinstance(data, dict):
                    data = [data]
                for s in data:
                    status = s.get("Status")
                    running = status in (4, "Running")
                    out.append({"name": s.get("Name", ""), "status": "running" if running else "stopped",
                                "sub": str(status), "description": s.get("DisplayName", "")})
            except json.JSONDecodeError:
                pass
        return out

    # ------------------------------------------------------------------ paquets
    def package_manager(self) -> str:
        if shutil.which("winget"):
            return "winget"
        if shutil.which("choco"):
            return "choco"
        return ""

    def install_packages(self, packages: Iterable[str], on_line: Callable[[str], None]) -> int:
        pm = self.package_manager()
        code = 0
        for pkg in packages:
            if pm == "winget":
                cmd = ["winget", "install", "--id", pkg, "-e", "--silent", "--accept-package-agreements",
                       "--accept-source-agreements"]
            elif pm == "choco":
                cmd = ["choco", "install", pkg, "-y"]
            else:
                on_line("Aucun gestionnaire de paquets (winget/chocolatey) détecté.")
                return 1
            on_line("$ " + " ".join(cmd))
            rc = self.stream(cmd, on_line)
            code = code or rc
        return code

    def remove_packages(self, packages: Iterable[str], on_line: Callable[[str], None]) -> int:
        pm = self.package_manager()
        code = 0
        for pkg in packages:
            if pm == "winget":
                cmd = ["winget", "uninstall", "--id", pkg, "-e", "--silent"]
            elif pm == "choco":
                cmd = ["choco", "uninstall", pkg, "-y"]
            else:
                on_line("Aucun gestionnaire de paquets détecté.")
                return 1
            on_line("$ " + " ".join(cmd))
            rc = self.stream(cmd, on_line)
            code = code or rc
        return code

    def package_installed(self, package: str) -> bool:
        pm = self.package_manager()
        if pm == "winget":
            r = self.run(["winget", "list", "--id", package, "-e"], timeout=60)
            return r.ok and package.lower() in r.stdout.lower()
        if pm == "choco":
            r = self.run(["choco", "list", "--local-only", "--exact", package], timeout=60)
            return r.ok and package.lower() in r.stdout.lower()
        return False

    # ------------------------------------------------------------------ pare-feu
    def firewall_backend(self) -> str:
        return "netsh"

    def firewall_status(self) -> dict:
        r = self.run(["netsh", "advfirewall", "show", "allprofiles", "state"], timeout=15)
        return {"backend": "netsh", "enabled": "ON" in r.stdout.upper()}

    def firewall_enable(self, enable: bool) -> CommandResult:
        return self.run(["netsh", "advfirewall", "set", "allprofiles", "state", "on" if enable else "off"], timeout=30)

    @staticmethod
    def _rule_name(port: str, protocol: str, action: str, source: str) -> str:
        return f"ToutPanel {action} {protocol}/{port}" + (f" from {source}" if source else "")

    def firewall_add(self, port: str, protocol: str, action: str, source: str, remark: str) -> CommandResult:
        cmd = ["netsh", "advfirewall", "firewall", "add", "rule",
               f"name={self._rule_name(port, protocol, action, source)}", "dir=in",
               f"action={'allow' if action == 'allow' else 'block'}", f"protocol={protocol}", f"localport={port}"]
        if source:
            cmd.append(f"remoteip={source}")
        return self.run(cmd, timeout=30)

    def firewall_remove(self, port: str, protocol: str, action: str, source: str, remark: str) -> CommandResult:
        return self.run(["netsh", "advfirewall", "firewall", "delete", "rule",
                         f"name={self._rule_name(port, protocol, action, source)}"], timeout=30)

    def reboot(self) -> CommandResult:
        return self.run(["shutdown", "/r", "/t", "5"], timeout=10)
