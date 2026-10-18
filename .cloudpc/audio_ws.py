import asyncio
import os
from pathlib import Path
from aiohttp import web

BASE = Path(__file__).resolve().parent

async def index(request):
    return web.FileResponse(
        BASE / "audio.html",
        headers={"Cache-Control": "no-store"}
    )

async def worklet(request):
    return web.FileResponse(
        BASE / "audio-worklet.js",
        headers={"Cache-Control": "no-store"}
    )

async def receive(ws):
    async for _ in ws:
        pass

async def stream(request):
    try:
        rate = int(request.query.get("rate", "48000"))
    except ValueError:
        raise web.HTTPBadRequest()

    if not 8000 <= rate <= 96000:
        raise web.HTTPBadRequest()

    ws = web.WebSocketResponse(
        heartbeat=20,
        compress=False
    )
    await ws.prepare(request)

    cmd = [
        "ffmpeg", "-nostdin",
        "-hide_banner", "-loglevel", "error",
        "-f", "pulse",
        "-fragment_size", "2048",
        "-i", "cloudpc.monitor",
        "-ac", "1",
        "-ar", str(rate),
        "-c:a", "pcm_s16le",
        "-f", "s16le",
        "pipe:1"
    ]

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
        env=os.environ.copy()
    )

    reader = asyncio.create_task(receive(ws))
    pending = b""

    try:
        while not reader.done():
            task = asyncio.create_task(
                proc.stdout.read(4096)
            )

            done, _ = await asyncio.wait(
                [task, reader],
                return_when=asyncio.FIRST_COMPLETED
            )

            if reader in done:
                task.cancel()
                await asyncio.gather(
                    task, return_exceptions=True
                )
                break

            chunk = task.result()

            if not chunk:
                break

            chunk = pending + chunk

            # PCM 16-bit requires complete samples
            if len(chunk) % 2:
                pending = chunk[-1:]
                chunk = chunk[:-1]
            else:
                pending = b""

            if chunk:
                await ws.send_bytes(chunk)

    except (ConnectionError, RuntimeError):
        pass

    finally:
        reader.cancel()
        await asyncio.gather(
            reader, return_exceptions=True
        )

        if proc.returncode is None:
            proc.terminate()
            try:
                await asyncio.wait_for(
                    proc.wait(), timeout=2
                )
            except asyncio.TimeoutError:
                proc.kill()
                await proc.wait()

        await ws.close()

    return ws

app = web.Application()
app.router.add_get("/", index)
app.router.add_get("/audio-worklet.js", worklet)
app.router.add_get("/ws", stream)

web.run_app(
    app,
    host="0.0.0.0",
    port=6081,
    access_log=None
)
