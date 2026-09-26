"""Abstraction du système d'exploitation (Linux / Windows)."""
from __future__ import annotations
from typing import Optional

from toutpanel.config import IS_WINDOWS
from toutpanel.platform.base import BasePlatform, CommandResult  # noqa: F401

_platform: Optional[BasePlatform] = None


def get_platform() -> BasePlatform:
    global _platform
    if _platform is None:
        if IS_WINDOWS:
            from toutpanel.platform.windows import WindowsPlatform

            _platform = WindowsPlatform()
        else:
            from toutpanel.platform.linux import LinuxPlatform

            _platform = LinuxPlatform()
    return _platform
