"""Gestion des bases de données (MySQL/MariaDB, PostgreSQL, SQLite)."""
from __future__ import annotations
from typing import Optional

import re
import shutil
from pathlib import Path

from sqlalchemy.orm import Session

from toutpanel import config
from toutpanel.models import Database
from toutpanel.platform import get_platform
from toutpanel.security import generate_password

NAME_RE = re.compile(r"^[a-zA-Z0-9_]{1,64}$")


class DbError(ValueError):
    pass


# --------------------------------------------------------------------------- identifiants root

def get_root_credentials(engine: str) -> dict:
    s = config.get_settings()
    return s.get(f"{engine}_root") or {"host": "localhost", "port": 3306 if engine == "mysql" else 5432,
                                       "user": "root" if engine == "mysql" else "postgres", "password": ""}


def set_root_credentials(engine: str, creds: dict) -> None:
    config.get_settings().set(f"{engine}_root", creds)


# --------------------------------------------------------------------------- MySQL

def _mysql_connect(creds: Optional[dict] = None):
    import pymysql

    c = creds or get_root_credentials("mysql")
    kwargs = dict(host=c.get("host", "localhost"), port=int(c.get("port", 3306)), user=c.get("user", "root"),
                  password=c.get("password", ""), connect_timeout=5, autocommit=True)
    if c.get("socket"):
        kwargs["unix_socket"] = c["socket"]
    try:
        return pymysql.connect(**kwargs)
    except Exception as e:
        # tentative via socket local (auth_socket) si aucun mot de passe
        if not config.IS_WINDOWS and not c.get("password"):
            for sock in ("/var/run/mysqld/mysqld.sock", "/run/mysqld/mysqld.sock", "/var/lib/mysql/mysql.sock"):
                if Path(sock).exists():
                    try:
                        return pymysql.connect(unix_socket=sock, user=c.get("user", "root"), password="",
                                               connect_timeout=5, autocommit=True)
                    except Exception:
                        continue
        raise DbError(f"Connexion MySQL impossible : {e}")


MYSQL_SOCKETS = ("/var/run/mysqld/mysqld.sock", "/run/mysqld/mysqld.sock", "/var/lib/mysql/mysql.sock")


def _mysql_cli(exe: str, creds: Optional[dict] = None) -> tuple[list[str], dict]:
    """Arguments et environnement pour mysql / mysqldump. Sans mot de passe sous Linux, force la socket Unix
    (authentification unix_socket de MariaDB)."""
    c = creds or get_root_credentials("mysql")
    env: dict = {}
    args = [exe, "-u", c.get("user", "root")]
    sock = c.get("socket") or next((s for s in MYSQL_SOCKETS if Path(s).exists()), None)
    if not c.get("password") and sock and not config.IS_WINDOWS and c.get("host", "localhost") in ("localhost", "127.0.0.1"):
        args += ["--protocol=socket", f"--socket={sock}"]
    else:
        args += ["-h", c.get("host", "localhost"), "-P", str(c.get("port", 3306))]
        env["MYSQL_PWD"] = c.get("password", "")
    return args, env


def mysql_status() -> dict:
    try:
        conn = _mysql_connect()
        with conn.cursor() as cur:
            cur.execute("SELECT VERSION()")
            version = cur.fetchone()[0]
        conn.close()
        return {"ok": True, "version": version}
    except DbError as e:
        return {"ok": False, "error": str(e)}


def mysql_create(name: str, user: str, password: str, host: str = "localhost") -> None:
    conn = _mysql_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS `{name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
            cur.execute("CREATE USER IF NOT EXISTS %s@%s IDENTIFIED BY %s", (user, host, password))
            cur.execute("ALTER USER %s@%s IDENTIFIED BY %s", (user, host, password))
            cur.execute(f"GRANT ALL PRIVILEGES ON `{name}`.* TO %s@%s", (user, host))
            cur.execute("FLUSH PRIVILEGES")
    finally:
        conn.close()


def mysql_drop(name: str, user: str, host: str = "localhost") -> None:
    conn = _mysql_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DROP DATABASE IF EXISTS `{name}`")
            if user and user != "root":
                cur.execute("DROP USER IF EXISTS %s@%s", (user, host))
            cur.execute("FLUSH PRIVILEGES")
    finally:
        conn.close()


def mysql_set_password(user: str, password: str, host: str = "localhost") -> None:
    conn = _mysql_connect()
    try:
        with conn.cursor() as cur:
            cur.execute("ALTER USER %s@%s IDENTIFIED BY %s", (user, host, password))
            cur.execute("FLUSH PRIVILEGES")
    finally:
        conn.close()


def mysql_list_databases() -> list[dict]:
    conn = _mysql_connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT table_schema, COALESCE(SUM(data_length+index_length),0), COUNT(*) FROM information_schema.tables "
                        "GROUP BY table_schema")
            return [{"name": r[0], "size": int(r[1]), "tables": int(r[2])} for r in cur.fetchall()]
    finally:
        conn.close()


def mysql_dump(name: str, out_path: Path) -> None:
    plat = get_platform()
    creds = get_root_credentials("mysql")
    exe = plat.which("mysqldump") or plat.which("mariadb-dump")
    if not exe:
        raise DbError("mysqldump introuvable")
    cmd, env = _mysql_cli(exe, creds)
    cmd += ["--single-transaction", "--routines", "--triggers", name]
    r = plat.run(cmd, timeout=3600, env=env)
    if not r.ok:
        raise DbError("mysqldump a échoué : " + r.stderr[:500])
    out_path.write_text(r.stdout, encoding="utf-8")


def mysql_import(name: str, sql_path: Path) -> None:
    plat = get_platform()
    creds = get_root_credentials("mysql")
    exe = plat.which("mysql") or plat.which("mariadb")
    if not exe:
        raise DbError("client mysql introuvable")
    cmd, env = _mysql_cli(exe, creds)
    cmd.append(name)
    r = plat.run(cmd, timeout=3600, env=env, input_text=sql_path.read_text(encoding="utf-8", errors="replace"))
    if not r.ok:
        raise DbError("import a échoué : " + r.stderr[:500])


# --------------------------------------------------------------------------- PostgreSQL

def _pg_connect(dbname: str = "postgres"):
    try:
        import psycopg
    except ImportError:
        raise DbError("Le module psycopg n'est pas installé (pip install 'toutpanel[postgres]')")
    c = get_root_credentials("postgres")
    try:
        return psycopg.connect(host=c.get("host", "localhost"), port=int(c.get("port", 5432)), user=c.get("user", "postgres"),
                               password=c.get("password", ""), dbname=dbname, connect_timeout=5, autocommit=True)
    except Exception as e:
        raise DbError(f"Connexion PostgreSQL impossible : {e}")


def postgres_status() -> dict:
    try:
        conn = _pg_connect()
        with conn.cursor() as cur:
            cur.execute("SHOW server_version")
            version = cur.fetchone()[0]
        conn.close()
        return {"ok": True, "version": version}
    except DbError as e:
        return {"ok": False, "error": str(e)}


def postgres_create(name: str, user: str, password: str) -> None:
    conn = _pg_connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_roles WHERE rolname=%s", (user,))
            if cur.fetchone():
                cur.execute(f'ALTER ROLE "{user}" WITH LOGIN PASSWORD %s', (password,))
            else:
                cur.execute(f'CREATE ROLE "{user}" WITH LOGIN PASSWORD %s', (password,))
            cur.execute("SELECT 1 FROM pg_database WHERE datname=%s", (name,))
            if not cur.fetchone():
                cur.execute(f'CREATE DATABASE "{name}" OWNER "{user}"')
            cur.execute(f'GRANT ALL PRIVILEGES ON DATABASE "{name}" TO "{user}"')
    finally:
        conn.close()


def postgres_drop(name: str, user: str) -> None:
    conn = _pg_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
            if user and user != "postgres":
                cur.execute(f'DROP ROLE IF EXISTS "{user}"')
    finally:
        conn.close()


def postgres_set_password(user: str, password: str) -> None:
    conn = _pg_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(f'ALTER ROLE "{user}" WITH PASSWORD %s', (password,))
    finally:
        conn.close()


def postgres_dump(name: str, out_path: Path) -> None:
    plat = get_platform()
    creds = get_root_credentials("postgres")
    exe = plat.which("pg_dump")
    if not exe:
        raise DbError("pg_dump introuvable")
    r = plat.run([exe, "-h", creds.get("host", "localhost"), "-p", str(creds.get("port", 5432)), "-U", creds.get("user", "postgres"), name],
                 timeout=3600, env={"PGPASSWORD": creds.get("password", "")})
    if not r.ok:
        raise DbError("pg_dump a échoué : " + r.stderr[:500])
    out_path.write_text(r.stdout, encoding="utf-8")


# --------------------------------------------------------------------------- façade

def engine_available(engine: str) -> bool:
    plat = get_platform()
    if engine == "mysql":
        return bool(plat.which("mysqld") or plat.which("mariadbd") or plat.which("mysql") or shutil.which("mysqld_safe")
                    or Path("/usr/sbin/mysqld").exists() or Path("/usr/sbin/mariadbd").exists())
    if engine == "postgres":
        return bool(plat.which("psql") or plat.which("pg_ctl"))
    return engine == "sqlite"


def create_database(db: Session, name: str, engine: str, username: str = "", password: str = "",
                    host: str = "localhost", remark: str = "") -> Database:
    if not NAME_RE.match(name):
        raise DbError("Nom de base invalide (lettres, chiffres, _ ; 64 max)")
    if engine not in ("mysql", "postgres", "sqlite"):
        raise DbError("Moteur inconnu")
    username = username or name
    if not NAME_RE.match(username):
        raise DbError("Nom d'utilisateur invalide")
    password = password or generate_password(16)
    if db.query(Database).filter(Database.name == name, Database.engine == engine).first():
        raise DbError("Cette base existe déjà dans le panel")
    if engine == "mysql":
        mysql_create(name, username, password, host if host in ("localhost", "127.0.0.1", "%") else host)
    elif engine == "postgres":
        postgres_create(name, username, password)
    else:
        (config.DATA_DIR / "sqlite").mkdir(parents=True, exist_ok=True)
        p = config.DATA_DIR / "sqlite" / f"{name}.db"
        import sqlite3

        sqlite3.connect(p).close()
        host = str(p)
    row = Database(name=name, engine=engine, username=username, password=password, host=host, remark=remark)
    db.add(row)
    db.flush()
    return row


def delete_database(db: Session, row: Database, drop: bool = True) -> None:
    if drop:
        if row.engine == "mysql":
            mysql_drop(row.name, row.username, row.host if row.host != str(config.DATA_DIR) else "localhost")
        elif row.engine == "postgres":
            postgres_drop(row.name, row.username)
        elif row.engine == "sqlite":
            Path(row.host).unlink(missing_ok=True)
    db.delete(row)
    db.flush()


def change_password(row: Database, password: str) -> None:
    if row.engine == "mysql":
        mysql_set_password(row.username, password, row.host)
    elif row.engine == "postgres":
        postgres_set_password(row.username, password)
    row.password = password


def dump_database(row: Database, out_path: Path) -> Path:
    if row.engine == "mysql":
        mysql_dump(row.name, out_path)
    elif row.engine == "postgres":
        postgres_dump(row.name, out_path)
    elif row.engine == "sqlite":
        shutil.copy2(row.host, out_path)
    return out_path


def engines_status() -> dict:
    return {
        "mysql": {"available": engine_available("mysql"), **(mysql_status() if engine_available("mysql") else {"ok": False})},
        "postgres": {"available": engine_available("postgres"), **(postgres_status() if engine_available("postgres") else {"ok": False})},
        "sqlite": {"available": True, "ok": True},
    }
