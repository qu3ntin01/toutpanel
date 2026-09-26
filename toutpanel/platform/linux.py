from __future__ import annotations

import os
import shutil
from typing import Callable, Iterable

from toutpanel.platform.base import BasePlatform, CommandResult


class LinuxPlatform(BasePlatform):
    name = "linux"

    def is_admin(self) -> bool:
        return hasattr(os, "geteuid") and os.geteuid() == 0

    def os_info(self) -> dict:
        info = super().os_info()
        try:
            data = {}
            with open("/etc/os-release", encoding="utf-8") as f:
                for line in f:
                    if "=" in line:
                        k, v = line.rstrip("\n").split("=", 1)
                        data[k] = v.strip('"')
            info["pretty"] = data.get("PRETTY_NAME", info["pretty"])
            info["distro_id"] = data.get("ID", "")
            info["distro_like"] = data.get("ID_LIKE", "")
        except OSError:
            info["distro_id"] = ""
        return info

    # ------------------------------------------------------------------ services
    def _has_systemd(self) -> bool:
        return shutil.which("systemctl") is not None and os.path.isdir("/run/systemd/system")

    def service_status(self, name: str) -> str:
        if self._has_systemd():
            r = self.run(["systemctl", "show", "-p", "LoadState", "-p", "ActiveState", name], timeout=15)
            props = dict(line.split("=", 1) for line in r.stdout.splitlines() if "=" in line)
            if props.get("LoadState") in (None, "not-found", "masked"):
                return "unknown"
            return "running" if props.get("ActiveState") == "active" else "stopped"
        if not (os.path.exists(f"/etc/init.d/{name}") or os.path.exists(f"/etc/rc.d/{name}")):
            return "unknown"
        r = self.run(["service", name, "status"], timeout=15)
        return "running" if r.ok else "stopped"

    def service_action(self, name: str, action: str) -> CommandResult:
        if action not in ("start", "stop", "restart", "reload", "enable", "disable"):
            return CommandResult(1, "", "action invalide")
        if self._has_systemd():
            if action == "enable":
                return self.run(["systemctl", "enable", "--now", name], timeout=60)
            return self.run(["systemctl", action, name], timeout=120)
        if action in ("enable", "disable"):
            return CommandResult(1, "", "systemd absent")
        return self.run(["service", name, action], timeout=120)

    def list_services(self) -> list[dict]:
        out: list[dict] = []
        if self._has_systemd():
            r = self.run(["systemctl", "list-units", "--type=service", "--all", "--no-pager", "--no-legend", "--plain"], timeout=30)
            for line in r.stdout.splitlines():
                parts = line.split(None, 4)
                if len(parts) < 4:
                    continue
                unit, load, active, sub = parts[:4]
                desc = parts[4] if len(parts) > 4 else ""
                out.append({"name": unit.replace(".service", ""), "status": "running" if active == "active" else "stopped",
                            "sub": sub, "description": desc})
        return out

    # ------------------------------------------------------------------ paquets
    def package_manager(self) -> str:
        for pm in ("apt-get", "dnf", "yum", "zypper", "pacman", "apk"):
            if shutil.which(pm):
                return pm
        return ""

    def _pm_cmd(self, action: str, packages: list[str]) -> tuple[list[str], dict]:
        pm = self.package_manager()
        env = {"DEBIAN_FRONTEND": "noninteractive"}
        if pm == "apt-get":
            if action == "install":
                return ["bash", "-c", "apt-get update -qq && apt-get install -y -qq " + " ".join(packages)], env
            return ["apt-get", "remove", "-y", "-qq", *packages], env
        if pm in ("dnf", "yum"):
            if action == "install":
                return [pm, "install", "-y", "--allowerasing", *packages], env
            return [pm, "remove", "-y", *packages], env
        if pm == "zypper":
            return ["zypper", "--non-interactive", "install" if action == "install" else "remove", *packages], env
        if pm == "pacman":
            return ["pacman", "-S" if action == "install" else "-R", "--noconfirm", *packages], env
        if pm == "apk":
            return ["apk", "add" if action == "install" else "del", *packages], env
        return [], env

    def install_packages(self, packages: Iterable[str], on_line: Callable[[str], None]) -> int:
        cmd, env = self._pm_cmd("install", list(packages))
        if not cmd:
            on_line("Aucun gestionnaire de paquets détecté.")
            return 1
        on_line("$ " + " ".join(cmd))
        return self.stream(cmd, on_line, env=env)

    def remove_packages(self, packages: Iterable[str], on_line: Callable[[str], None]) -> int:
        cmd, env = self._pm_cmd("remove", list(packages))
        if not cmd:
            on_line("Aucun gestionnaire de paquets détecté.")
            return 1
        on_line("$ " + " ".join(cmd))
        return self.stream(cmd, on_line, env=env)

    def package_installed(self, package: str) -> bool:
        pm = self.package_manager()
        if pm == "apt-get":
            r = self.run(["dpkg-query", "-W", "-f=${Status}", package], timeout=15)
            return r.ok and "install ok installed" in r.stdout
        if pm in ("dnf", "yum"):
            return self.run(["rpm", "-q", package], timeout=15).ok
        if pm == "pacman":
            return self.run(["pacman", "-Q", package], timeout=15).ok
        if pm == "apk":
            return self.run(["apk", "info", "-e", package], timeout=15).ok
        return False

    def package_available(self, package: str) -> bool:
        pm = self.package_manager()
        if pm == "apt-get":
            r = self.run(["apt-cache", "policy", package], timeout=30)
            return r.ok and "Candidate:" in r.stdout and "Candidate: (none)" not in r.stdout
        if pm in ("dnf", "yum"):
            return self.run([pm, "-q", "list", "--available", package], timeout=120).ok or self.package_installed(package)
        if pm == "apk":
            r = self.run(["apk", "search", "-e", package], timeout=30)
            return r.ok and bool(r.stdout.strip())
        if pm == "pacman":
            return self.run(["pacman", "-Si", package], timeout=30).ok
        return True

    # ------------------------------------------------------------------ pare-feu
    def firewall_backend(self) -> str:
        if shutil.which("ufw"):
            return "ufw"
        if shutil.which("firewall-cmd"):
            return "firewalld"
        if shutil.which("iptables"):
            return "iptables"
        return ""

    def firewall_status(self) -> dict:
        b = self.firewall_backend()
        enabled = False
        if b == "ufw":
            enabled = "Status: active" in self.run(["ufw", "status"], timeout=15).stdout
        elif b == "firewalld":
            enabled = self.run(["firewall-cmd", "--state"], timeout=15).stdout.strip() == "running"
        elif b == "iptables":
            enabled = True
        return {"backend": b, "enabled": enabled}

    def firewall_enable(self, enable: bool) -> CommandResult:
        b = self.firewall_backend()
        if b == "ufw":
            return self.run(["ufw", "--force", "enable" if enable else "disable"], timeout=30)
        if b == "firewalld":
            return self.service_action("firewalld", "start" if enable else "stop")
        return CommandResult(1, "", "pare-feu non pris en charge")

    def firewall_add(self, port: str, protocol: str, action: str, source: str, remark: str) -> CommandResult:
        b = self.firewall_backend()
        port = port.replace("-", ":") if b in ("ufw", "iptables") else port
        if b == "ufw":
            cmd = ["ufw", action]
            if source:
                cmd += ["from", source, "to", "any", "port", port, "proto", protocol]
            else:
                cmd += [f"{port}/{protocol}"]
            if remark:
                cmd += ["comment", remark[:64]]
            return self.run(cmd, timeout=30)
        if b == "firewalld":
            if source:
                rule = f'rule family="ipv4" source address="{source}" port port="{port}" protocol="{protocol}" {"accept" if action == "allow" else "drop"}'
                r = self.run(["firewall-cmd", "--permanent", "--add-rich-rule", rule], timeout=30)
            else:
                if action == "allow":
                    r = self.run(["firewall-cmd", "--permanent", f"--add-port={port}/{protocol}"], timeout=30)
                else:
                    rule = f'rule family="ipv4" port port="{port}" protocol="{protocol}" drop'
                    r = self.run(["firewall-cmd", "--permanent", "--add-rich-rule", rule], timeout=30)
            self.run(["firewall-cmd", "--reload"], timeout=30)
            return r
        if b == "iptables":
            cmd = ["iptables", "-I", "INPUT", "-p", protocol, "--dport", port]
            if source:
                cmd += ["-s", source]
            cmd += ["-j", "ACCEPT" if action == "allow" else "DROP"]
            return self.run(cmd, timeout=30)
        return CommandResult(1, "", "pare-feu non pris en charge")

    def firewall_remove(self, port: str, protocol: str, action: str, source: str, remark: str) -> CommandResult:
        b = self.firewall_backend()
        port = port.replace("-", ":") if b in ("ufw", "iptables") else port
        if b == "ufw":
            cmd = ["ufw", "delete", action]
            if source:
                cmd += ["from", source, "to", "any", "port", port, "proto", protocol]
            else:
                cmd += [f"{port}/{protocol}"]
            return self.run(cmd, timeout=30)
        if b == "firewalld":
            if source:
                rule = f'rule family="ipv4" source address="{source}" port port="{port}" protocol="{protocol}" {"accept" if action == "allow" else "drop"}'
                r = self.run(["firewall-cmd", "--permanent", "--remove-rich-rule", rule], timeout=30)
            elif action == "allow":
                r = self.run(["firewall-cmd", "--permanent", f"--remove-port={port}/{protocol}"], timeout=30)
            else:
                rule = f'rule family="ipv4" port port="{port}" protocol="{protocol}" drop'
                r = self.run(["firewall-cmd", "--permanent", "--remove-rich-rule", rule], timeout=30)
            self.run(["firewall-cmd", "--reload"], timeout=30)
            return r
        if b == "iptables":
            cmd = ["iptables", "-D", "INPUT", "-p", protocol, "--dport", port]
            if source:
                cmd += ["-s", source]
            cmd += ["-j", "ACCEPT" if action == "allow" else "DROP"]
            return self.run(cmd, timeout=30)
        return CommandResult(1, "", "pare-feu non pris en charge")

    # ------------------------------------------------------------------ famille RHEL : EPEL / CRB
    def rhel_info(self) -> dict:
        info = self.os_info()
        ids = f"{info.get('distro_id', '')} {info.get('distro_like', '')}".lower()
        major = ""
        try:
            with open("/etc/os-release", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("VERSION_ID="):
                        major = line.split("=", 1)[1].strip().strip('"').split(".")[0]
        except OSError:
            pass
        return {"is_rhel_like": any(k in ids for k in ("rhel", "centos", "fedora", "rocky", "alma")), "is_fedora": "fedora" in info.get("distro_id", "").lower(),
                "is_rhel_proper": info.get("distro_id", "").lower() == "rhel", "major": major, "id": info.get("distro_id", "").lower()}

    def ensure_epel(self, on_line=None) -> bool:
        """Active EPEL et CRB/PowerTools sur Alma/Rocky/RHEL (inutile sur Fedora)."""
        log = on_line or (lambda _: None)
        ri = self.rhel_info()
        if not ri["is_rhel_like"] or ri["is_fedora"]:
            return True
        pm = self.package_manager() or "dnf"
        if not self.package_installed("epel-release"):
            log("Activation du dépôt EPEL…")
            if ri["is_rhel_proper"]:
                self.stream([pm, "install", "-y", f"https://dl.fedoraproject.org/pub/epel/epel-release-latest-{ri['major']}.noarch.rpm"], log)
            else:
                self.stream([pm, "install", "-y", "epel-release"], log)
        if ri["is_rhel_proper"]:
            self.run(["subscription-manager", "repos", "--enable", f"codeready-builder-for-rhel-{ri['major']}-{os.uname().machine}-rpms"], timeout=120)
        else:
            r = self.run([pm, "config-manager", "--set-enabled", "crb"], timeout=60)
            if not r.ok:
                self.run([pm, "config-manager", "--set-enabled", "powertools"], timeout=60)
        return self.package_installed("epel-release")

    # ------------------------------------------------------------------ SELinux
    def selinux_status(self) -> str:
        if shutil.which("getenforce"):
            return self.run(["getenforce"], timeout=10).stdout.strip().lower()
        try:
            with open("/sys/fs/selinux/enforce") as f:
                return "enforcing" if f.read().strip() == "1" else "permissive"
        except OSError:
            return "disabled" if os.path.isdir("/sys/fs/selinux") else ""

    def selinux_setup(self, www_root: str, home: str, vmail: str = "/var/vmail") -> list[str]:
        """Déclare les contextes SELinux nécessaires à nginx/apache/php-fpm/dovecot et active les booléens utiles."""
        msgs: list[str] = []
        st = self.selinux_status()
        if st not in ("enforcing", "permissive"):
            return [f"SELinux : {st or 'absent'} (rien à faire)"]
        if not shutil.which("semanage"):
            self.run([self.package_manager() or "dnf", "install", "-y", "policycoreutils-python-utils"], timeout=600)
        if not shutil.which("semanage"):
            return ["SELinux actif mais semanage indisponible : installez policycoreutils-python-utils"]
        contexts = [
            (f"{www_root}(/.*)?", "httpd_sys_rw_content_t"), (f"{home}/logs/sites(/.*)?", "httpd_log_t"),
            (f"{home}/ssl(/.*)?", "cert_t"), (f"{home}/vhost(/.*)?", "httpd_config_t"), (f"{vmail}(/.*)?", "mail_spool_t"),
        ]
        for pattern, ctype in contexts:
            r = self.run(["semanage", "fcontext", "-a", "-t", ctype, pattern], timeout=120)
            if not r.ok and "already defined" in r.output:
                r = self.run(["semanage", "fcontext", "-m", "-t", ctype, pattern], timeout=120)
            msgs.append(f"{pattern} → {ctype} : {'ok' if r.ok else r.output[:120]}")
        for path in (www_root, f"{home}/logs", f"{home}/ssl", f"{home}/vhost", vmail):
            if os.path.exists(path):
                self.run(["restorecon", "-R", path], timeout=600)
        for boolean in ("httpd_can_network_connect", "httpd_can_network_connect_db", "httpd_can_sendmail", "httpd_setrlimit"):
            r = self.run(["setsebool", "-P", boolean, "1"], timeout=120)
            msgs.append(f"{boolean}=1 : {'ok' if r.ok else r.output[:80]}")
        return msgs

    def restorecon(self, path: str) -> None:
        if shutil.which("restorecon") and self.selinux_status() in ("enforcing", "permissive"):
            self.run(["restorecon", "-R", path], timeout=600)

    # ------------------------------------------------------------------ divers
    def web_user(self) -> str:
        import pwd

        for u in ("www-data", "nginx", "apache", "http", "www"):
            try:
                pwd.getpwnam(u)
                return u
            except KeyError:
                continue
        return ""

    def chown_web(self, path: str) -> None:
        user = self.web_user()
        if not user or not self.is_admin():
            return
        self.run(["chown", "-R", f"{user}:{user}", path], timeout=120)
        self.restorecon(path)

    def reboot(self) -> CommandResult:
        return self.run(["shutdown", "-r", "now"], timeout=10)
