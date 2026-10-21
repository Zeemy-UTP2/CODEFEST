"""
Smart Campus Bus Tracker - backend API (Hazeem, Backend and API)

Start:   py -m uvicorn main:app --reload
Docs:    http://127.0.0.1:8000/docs
App:     http://127.0.0.1:8000/

Data comes from Roy's Oracle database when ORACLE_DSN is set in .env,
otherwise from a local copy of the same demo data (see store.py).
"""
import json
import os
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict

import rules
from store import open_store
from traccar_sync import TraccarSync

HERE = Path(__file__).parent

# Settings come from a .env file (see .env.example) or the terminal.
try:
    from dotenv import load_dotenv
    load_dotenv(HERE / ".env")
except ImportError:
    pass
SETTINGS = dict(os.environ)

store = open_store(SETTINGS)
traccar = TraccarSync(SETTINGS, store)


@asynccontextmanager
async def lifespan(_app):
    traccar.start()   # only runs if Traccar is configured in .env
    yield
    traccar.stop()


app = FastAPI(
    title="Smart Campus Bus Tracker API",
    description="CodeFest'26. DEMO/SIMULATED DATA - not a real live UTP service. ETAs are estimates.",
    version="1.0",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------
# Location updates (from a GPS sender, the simulator or Traccar)
# ---------------------------------------------------------------------
class LocationUpdate(BaseModel):
    # strict: "4.38" as text is a BAD_TYPE, not silently turned into a number.
    # Fields are optional here so a MISSING field gets Roy's MISSING_FIELD reason.
    model_config = ConfigDict(strict=True)
    busId: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    timestamp: Optional[str] = None
    speedKmh: Optional[float] = None
    accuracyM: Optional[float] = None
    dataSource: Optional[str] = None


@app.exception_handler(RequestValidationError)
async def bad_request_body(request: Request, error: RequestValidationError):
    """Turns broken JSON / wrong types into Roy's reason codes and logs them."""
    if request.url.path == "/api/locations":
        body = await request.body()
        try:
            is_object = isinstance(json.loads(body), dict)
        except ValueError:
            is_object = False
        reason = "BAD_TYPE" if is_object else "MALFORMED_PAYLOAD"
        bus_id = None
        if is_object:
            candidate = json.loads(body).get("busId")
            bus_id = candidate if isinstance(candidate, str) else None
        store.log_reject(reason, bus_id)
        return JSONResponse(status_code=400, content={"outcome": "REJECT", "reason": reason,
                                                      "details": error.errors()})
    return JSONResponse(status_code=422, content={"detail": error.errors()})


@app.post("/api/locations", tags=["GPS"])
def send_location(update: LocationUpdate):
    """
    One GPS update. Example body:
    {"busId": "BUS-01", "latitude": 4.3827, "longitude": 100.9692,
     "timestamp": "2026-10-21T08:30:00Z", "speedKmh": 18, "dataSource": "SIMULATED"}

    200 = ACCEPT or IGNORE_* (duplicate/older, safe to resend). 400 = REJECT with a reason code.
    """
    outcome, reason = store.apply_update(update.model_dump())
    return JSONResponse(status_code=400 if outcome == "REJECT" else 200,
                        content={"outcome": outcome, "reason": reason})


# ---------------------------------------------------------------------
# Data for the student app
# ---------------------------------------------------------------------
@app.get("/api/health", tags=["System"])
def health():
    return {"status": "ok", "mode": store.mode, "notice": store.notice,
            "traccar": traccar.status(), "serverTime": rules.to_iso_utc(rules.utc_now())}


@app.get("/api/config", tags=["System"])
def config():
    return store.config()


@app.get("/api/routes", tags=["Routes and stops"])
def routes():
    return store.routes_json()


@app.get("/api/stops", tags=["Routes and stops"])
def stops():
    return store.stops_json()


@app.get("/api/stops/{stop_id}/arrivals", tags=["Routes and stops"])
def stop_arrivals(stop_id: str):
    """Buses serving this stop, soonest first, with distance and ETA (an estimate)."""
    result = store.arrivals(stop_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Unknown stop")
    return result


@app.get("/api/buses", tags=["Buses"])
def buses():
    """Every bus with its latest location, age, freshness and display status."""
    return store.bus_status()


@app.get("/api/buses/{bus_id}", tags=["Buses"])
def bus_detail(bus_id: str):
    """One bus plus the stops on its route, nearest first, with ETA."""
    result = store.next_stops(bus_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Unknown bus")
    return result


# ---------------------------------------------------------------------
# Demo and debugging
# ---------------------------------------------------------------------
@app.post("/api/demo/reset", tags=["Demo"])
def demo_reset():
    """Puts the demo buses back to their starting positions, re-timed to now."""
    store.reset_demo()
    return {"status": "demo data reloaded"}


@app.get("/api/log", tags=["Demo"])
def update_log(limit: int = 50):
    """The latest location updates and what happened to each (accepted, ignored, rejected)."""
    return store.recent_log(max(1, min(limit, 500)))


# The student web app (static/index.html). Mounted last so /api and /docs win.
app.mount("/", StaticFiles(directory=HERE / "static", html=True), name="app")
