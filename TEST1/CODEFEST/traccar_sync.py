"""
Optional: feed real phone GPS from Traccar into the tracker.

When TRACCAR_EMAIL, TRACCAR_PASSWORD and TRACCAR_DEVICE_MAP are set in .env,
this checks Traccar every few seconds and sends each new phone position to the
store as a LIVE update for the mapped bus - through the same validation rules
as every other update.

TRACCAR_DEVICE_MAP example:  zeem-bus01=BUS-04,keanu-phone=BUS-02
(left side = device name on the Traccar website, right side = bus ID)
"""
import threading
from datetime import datetime, timezone

import rules


class TraccarSync:
    def __init__(self, settings, store):
        self.url = settings.get("TRACCAR_URL", "https://demo.traccar.org").rstrip("/")
        self.email = settings.get("TRACCAR_EMAIL")
        self.password = settings.get("TRACCAR_PASSWORD")
        self.interval = float(settings.get("TRACCAR_POLL_S", "5"))
        self.device_map = {}
        for pair in settings.get("TRACCAR_DEVICE_MAP", "").split(","):
            if "=" in pair:
                device, bus = pair.split("=", 1)
                self.device_map[device.strip()] = bus.strip()
        self.store = store
        self._stop = threading.Event()
        self._last_fix = {}
        self.last_error = None
        self.last_result = None

    @property
    def enabled(self):
        return bool(self.email and self.password and self.device_map)

    def status(self):
        if not self.enabled:
            return {"enabled": False}
        return {"enabled": True, "devices": self.device_map, "lastResult": self.last_result, "lastError": self.last_error}

    def start(self):
        if self.enabled:
            threading.Thread(target=self._run, daemon=True).start()

    def stop(self):
        self._stop.set()

    def _run(self):
        while not self._stop.is_set():
            try:
                self.poll_once()
                self.last_error = None
            except Exception as error:  # network down, wrong password... keep trying
                self.last_error = str(error)
            self._stop.wait(self.interval)

    def poll_once(self):
        import requests

        auth = (self.email, self.password)
        devices = requests.get(f"{self.url}/api/devices", auth=auth, timeout=10)
        devices.raise_for_status()
        positions = requests.get(f"{self.url}/api/positions", auth=auth, timeout=10)
        positions.raise_for_status()
        names = {d["id"]: d["name"] for d in devices.json()}

        for p in positions.json():
            name = names.get(p["deviceId"])
            bus_id = self.device_map.get(name)
            if not bus_id or self._last_fix.get(name) == p.get("fixTime"):
                continue  # not one of our buses, or nothing new
            self._last_fix[name] = p.get("fixTime")
            fix = datetime.fromisoformat(p["fixTime"]).astimezone(timezone.utc)
            speed_knots = p.get("speed")
            outcome, reason = self.store.apply_update({
                "busId": bus_id,
                "latitude": p["latitude"],
                "longitude": p["longitude"],
                "timestamp": rules.to_iso_utc(fix),
                "speedKmh": round(speed_knots * 1.852, 1) if speed_knots is not None else None,
                "accuracyM": p.get("accuracy"),
                "dataSource": "LIVE",
            })
            self.last_result = f"{name} -> {bus_id}: {outcome}/{reason}"
