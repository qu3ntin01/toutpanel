from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from toutpanel.api.deps import ws_user
from toutpanel.db import session_scope
from toutpanel.services.terminal import TerminalSession

router = APIRouter(tags=["terminal"])


@router.websocket("/ws/terminal")
async def terminal_ws(websocket: WebSocket):
    with session_scope() as db:
        user = ws_user(websocket, db)
    if not user:
        await websocket.close(code=4401)
        return
    await websocket.accept()
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue[bytes] = asyncio.Queue()

    def on_output(data: bytes):
        loop.call_soon_threadsafe(queue.put_nowait, data)

    term = TerminalSession(on_output)
    try:
        term.start()
    except Exception as e:
        await websocket.send_text(f"\r\nImpossible de démarrer le terminal : {e}\r\n")
        await websocket.close()
        return

    async def pump():
        while True:
            data = await queue.get()
            try:
                await websocket.send_bytes(data)
            except Exception:
                break

    pump_task = asyncio.create_task(pump())
    try:
        while True:
            msg = await websocket.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            if msg.get("bytes") is not None:
                term.write(msg["bytes"])
            elif msg.get("text") is not None:
                text = msg["text"]
                if text.startswith("{"):
                    try:
                        ctl = json.loads(text)
                        if ctl.get("type") == "resize":
                            term.resize(int(ctl.get("cols", 120)), int(ctl.get("rows", 32)))
                            continue
                    except (ValueError, TypeError):
                        pass
                term.write(text.encode("utf-8"))
    except WebSocketDisconnect:
        pass
    finally:
        pump_task.cancel()
        term.close()
