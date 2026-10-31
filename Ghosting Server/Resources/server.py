import asyncio
import atexit
import inspect
import os
import threading
from contextlib import AsyncExitStack

from flask import Flask, request, jsonify
from pymobiledevice3.remote.rsd_tunnel import PreferredRsdTunnel
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

HOST = os.environ.get("LOC_HOST", "0.0.0.0")
PORT = int(os.environ.get("LOC_PORT", "5001"))
TOKEN = os.environ.get("LOC_TOKEN")   # optionnel : exige le header X-Token
UDID = os.environ.get("LOC_UDID")     # optionnel : si plusieurs appareils


async def _maybe_await(value):
    return await value if inspect.isawaitable(value) else value


class LocationSession:
    """Garde un tunnel + une session DVT ouverts dans un thread asyncio dédié."""

    def __init__(self):
        self.loop = asyncio.new_event_loop()
        threading.Thread(target=self.loop.run_forever, daemon=True).start()
        self._stack = None
        self._sim = None
        self._current = None
        self._lock = asyncio.run_coroutine_threadsafe(self._make_lock(), self.loop).result()

    @staticmethod
    async def _make_lock():
        return asyncio.Lock()

    def run(self, coro, timeout=40):
        return asyncio.run_coroutine_threadsafe(coro, self.loop).result(timeout)

    async def _connect(self):
        await self._close()
        stack = AsyncExitStack()
        try:
            rsd = await stack.enter_async_context(PreferredRsdTunnel(serial=UDID))
            dvt = await stack.enter_async_context(DvtProvider(rsd))
            sim = LocationSimulation(dvt)
            if hasattr(sim, "__aenter__"):
                sim = await stack.enter_async_context(sim)
        except BaseException:
            await stack.aclose()
            raise
        self._stack, self._sim = stack, sim
        print("🔌 Session DVT ouverte")

    async def _close(self):
        if self._stack:
            try:
                await self._stack.aclose()
            except Exception as e:
                print(f"(fermeture session : {e!r})")
        self._stack = self._sim = self._current = None

    async def set(self, lat, lon):
        async with self._lock:
            for attempt in (1, 2):
                try:
                    if self._sim is None:
                        await self._connect()
                    await _maybe_await(self._sim.set(lat, lon))
                    self._current = (lat, lon)
                    return
                except Exception:
                    await self._close()      # session morte : on repart de zéro
                    if attempt == 2:
                        raise

    async def clear(self):
        """Efface la position simulée PUIS ferme la session : l'iPhone retrouve sa vraie position."""
        async with self._lock:
            if self._sim is not None:
                try:
                    await _maybe_await(self._sim.clear())
                except Exception as e:
                    print(f"(clear : {e!r})")
            await self._close()

    def current(self):
        return self._current


session = LocationSession()
atexit.register(lambda: session.run(session.clear(), timeout=10))

app = Flask(__name__)


@app.before_request
def _auth():
    if TOKEN and request.headers.get("X-Token") != TOKEN:
        return jsonify({"status": "error", "message": "Non autorisé"}), 401


@app.route("/set-location", methods=["POST"])
def set_location():
    data = request.get_json(silent=True) or {}
    try:
        lat = float(data.get("latitude"))
        lon = float(data.get("longitude"))
    except (TypeError, ValueError):
        return jsonify({"status": "error", "message": "Coordonnées manquantes ou invalides"}), 400
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return jsonify({"status": "error", "message": "Coordonnées hors limites"}), 400

    try:
        session.run(session.set(lat, lon))
    except Exception as e:
        print(f"❌ Erreur : {e!r}")
        return jsonify({"status": "error", "message": repr(e)}), 500

    print(f"📍 Position injectée : {lat}, {lon}")
    return jsonify({"status": "success", "latitude": lat, "longitude": lon})


@app.route("/clear-location", methods=["POST"])
def clear_location():
    try:
        session.run(session.clear())
    except Exception as e:
        print(f"❌ Erreur clear : {e!r}")
        return jsonify({"status": "error", "message": repr(e)}), 500
    print("🧹 Simulation arrêtée, position réelle restaurée")
    return jsonify({"status": "success"})


@app.route("/status", methods=["GET"])
def status():
    cur = session.current()
    return jsonify({"active": cur is not None,
                    "latitude": cur[0] if cur else None,
                    "longitude": cur[1] if cur else None})


if __name__ == "__main__":
    app.run(host=HOST, port=PORT, threaded=True)