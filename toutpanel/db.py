"""Accès base de données (SQLite via SQLAlchemy)."""
from __future__ import annotations

from contextlib import contextmanager

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from toutpanel import config


class Base(DeclarativeBase):
    pass


_engine = None
_SessionLocal = None


def get_engine():
    global _engine, _SessionLocal
    if _engine is None:
        config.ensure_dirs()
        _engine = create_engine(f"sqlite:///{config.DB_PATH}", connect_args={"check_same_thread": False, "timeout": 30}, future=True)

        @event.listens_for(_engine, "connect")
        def _pragmas(dbapi_conn, _):
            cur = dbapi_conn.cursor()
            cur.execute("PRAGMA journal_mode=WAL")
            cur.execute("PRAGMA foreign_keys=ON")
            cur.execute("PRAGMA busy_timeout=30000")
            cur.close()

        _SessionLocal = sessionmaker(bind=_engine, expire_on_commit=False, future=True)
    return _engine


def init_db() -> None:
    from toutpanel import models  # noqa: F401  (enregistre les tables)

    engine = get_engine()
    Base.metadata.create_all(engine)
    _migrate(engine)
    config.restrict_file(config.DB_PATH)


def _migrate(engine) -> None:
    """Ajoute les colonnes manquantes aux tables existantes (SQLite ne le fait pas via create_all)."""
    from sqlalchemy import inspect, text

    insp = inspect(engine)
    with engine.begin() as conn:
        for table in Base.metadata.sorted_tables:
            if not insp.has_table(table.name):
                continue
            existing = {c["name"] for c in insp.get_columns(table.name)}
            for col in table.columns:
                if col.name in existing:
                    continue
                ctype = col.type.compile(engine.dialect)
                default = ""
                if col.default is not None and getattr(col.default, "arg", None) is not None and not callable(col.default.arg):
                    arg = col.default.arg
                    default = " DEFAULT " + ("1" if arg is True else "0" if arg is False else repr(arg) if isinstance(arg, str) else str(arg))
                conn.execute(text(f'ALTER TABLE "{table.name}" ADD COLUMN "{col.name}" {ctype}{default}'))


@contextmanager
def session_scope():
    get_engine()
    db: Session = _SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def get_db():
    """Dépendance FastAPI."""
    get_engine()
    db: Session = _SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _db_dependency():
    """Dépendance FastAPI : la session est validée AVANT l'envoi de la réponse (scope function),
    pour qu'une requête suivante voie toujours les données commitées."""
    from fastapi import Depends

    try:
        return Depends(get_db, scope="function")
    except TypeError:  # FastAPI < 0.118
        return Depends(get_db)


DbDep = _db_dependency()


def reset_engine() -> None:
    global _engine, _SessionLocal
    if _engine is not None:
        _engine.dispose()
    _engine = None
    _SessionLocal = None
