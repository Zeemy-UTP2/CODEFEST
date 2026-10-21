"""Reference implementation of the Smart Campus Bus Tracker data-quality rules.

Mirrors oracle/02_package.sql (pkg_bus_tracker) rule for rule. Pure Python,
no packages needed. Use it:
  * as the executable specification (tests/test_data_quality.py proves it);
  * by Hazeem as a port source, or to pre-check JSON types (rules 1 and 3)
    BEFORE calling the Oracle procedure.

ALL DEMO DATA IS SIMULATED. Distances come from approximate demo coordinates.
"""
import math
import re
from datetime import datetime, timezone

R_EARTH_M = 6371000.0

# Defaults = rows of system_config in the seed (v1.2). Pass the real table in production.
DEFAULT_CONFIG = {
    "update_interval_s": 5, "stale_after_s": 30, "offline_after_s": 120,
    "max_future_skew_s": 60, "max_jump_speed_kmh": 100, "default_avg_speed_kmh": 20,
    "arrival_radius_m": 30,
    "bbox_min_lat": 4.34, "bbox_max_lat": 4.43, "bbox_min_lng": 100.92, "bbox_max_lng": 101.02,
}

_TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def haversine_m(lat1, lng1, lat2, lng2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R_EARTH_M * math.asin(math.sqrt(min(1.0, h)))


def parse_iso_utc(text):
    """Strict YYYY-MM-DDTHH:MM:SSZ -> aware UTC datetime, or None."""
    if not isinstance(text, str) or not _TS_RE.match(text) or text.endswith("\n"):
        return None
    try:
        return datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def to_iso_utc(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def validate_location_update(payload, stored, known_buses, now, config=DEFAULT_CONFIG):
    """Return (outcome, reason_code). `stored` = None or dict(latitude, longitude, timestamp ISO).
    First failing check decides the outcome. Numbering = docs/02 data quality rules."""
    # 1
    if not isinstance(payload, dict):
        return "REJECT", "MALFORMED_PAYLOAD"
    # 2
    for k in ("busId", "latitude", "longitude", "timestamp"):
        if payload.get(k) is None:
            return "REJECT", "MISSING_FIELD"
    # 3
    if not isinstance(payload["busId"], str) or not _is_number(payload["latitude"]) \
            or not _is_number(payload["longitude"]):
        return "REJECT", "BAD_TYPE"
    # 3a (v1.2)
    src = payload.get("dataSource") or "SIMULATED"
    sp, ac = payload.get("speedKmh"), payload.get("accuracyM")
    if src not in ("LIVE", "MANUAL", "SIMULATED") \
            or (sp is not None and (not _is_number(sp) or sp < 0)) \
            or (ac is not None and (not _is_number(ac) or ac < 0)):
        return "REJECT", "BAD_OPTIONAL_FIELD"
    lat, lng = payload["latitude"], payload["longitude"]
    # 4
    if payload["busId"] not in known_buses:
        return "REJECT", "UNKNOWN_BUS"
    # 5
    if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        return "REJECT", "OUT_OF_RANGE"
    # 6
    if not (config["bbox_min_lat"] <= lat <= config["bbox_max_lat"]
            and config["bbox_min_lng"] <= lng <= config["bbox_max_lng"]):
        return "REJECT", "OUTSIDE_SERVICE_AREA"
    # 7
    ts = parse_iso_utc(payload["timestamp"])
    if ts is None:
        return "REJECT", "BAD_TIMESTAMP"
    # 8
    if (ts - now).total_seconds() > config["max_future_skew_s"]:
        return "REJECT", "FUTURE_TIMESTAMP"
    if stored is not None:
        old = parse_iso_utc(stored["timestamp"])
        # 9 / 10
        if ts == old:
            return "IGNORE_DUPLICATE", "DUPLICATE_TIMESTAMP"
        if ts < old:
            return "IGNORE_OLDER", "OLDER_THAN_STORED"
        # 11
        dist = haversine_m(stored["latitude"], stored["longitude"], lat, lng)
        dt = (ts - old).total_seconds()
        if dist >= 50 and dt > 0 and (dist / dt) * 3.6 > config["max_jump_speed_kmh"]:
            return "REJECT", "IMPLAUSIBLE_JUMP"
    return "ACCEPT", "OK"


def freshness(age_seconds, config=DEFAULT_CONFIG):
    if age_seconds is None:
        return "UNAVAILABLE"
    if age_seconds <= config["stale_after_s"]:
        return "LIVE"
    if age_seconds <= config["offline_after_s"]:
        return "STALE"
    return "OFFLINE"


def display_status(service_state, fresh):
    if service_state == "OUT_OF_SERVICE":
        return "NOT_IN_SERVICE"
    return {"LIVE": "ACTIVE", "STALE": "STALE", "OFFLINE": "OFFLINE"}.get(fresh, "NO_DATA")


def eta_minutes(distance_m, speed_kmh):
    """minutes = distance / speed. None for missing/negative distance or missing/zero/negative speed."""
    if not _is_number(distance_m) or distance_m < 0 or not _is_number(speed_kmh) or speed_kmh <= 0:
        return None
    return round(distance_m / (speed_kmh * 1000 / 60), 1)


def remaining_distance_m(route, points, route_stops, lat, lng, stop_id, config=DEFAULT_CONFIG):
    """Route-aware distance still to travel to `stop_id` (metres) or None.
    route: dict(isLoop, totalLengthM). points: ordered dicts (latitude, longitude, cumulativeDistanceM).
    route_stops: list of dicts (stopId, cumulativeDistanceM)."""
    stop = next((s for s in route_stops if s["stopId"] == stop_id), None)
    if stop is None or not points:
        return None
    k = R_EARTH_M * math.pi / 180
    best_d, bus_cum = None, None
    n = len(points)
    for i, p in enumerate(points):
        if i + 1 < n:
            q = points[i + 1]
            lat2, lng2, c2 = q["latitude"], q["longitude"], q["cumulativeDistanceM"]
        elif route["isLoop"]:
            q = points[0]
            lat2, lng2, c2 = q["latitude"], q["longitude"], route["totalLengthM"]
        else:
            continue
        cosl = math.cos(math.radians(p["latitude"]))
        sx, sy = (lng2 - p["longitude"]) * k * cosl, (lat2 - p["latitude"]) * k
        px, py = (lng - p["longitude"]) * k * cosl, (lat - p["latitude"]) * k
        len2 = sx * sx + sy * sy
        t = 0.0 if len2 == 0 else max(0.0, min(1.0, (px * sx + py * sy) / len2))
        d = math.hypot(px - t * sx, py - t * sy)
        if best_d is None or d < best_d:
            best_d, bus_cum = d, p["cumulativeDistanceM"] + t * (c2 - p["cumulativeDistanceM"])
    if best_d is None:
        return None
    rem = stop["cumulativeDistanceM"] - bus_cum
    if rem < 0:
        if -rem <= config["arrival_radius_m"]:
            return 0
        if route["isLoop"]:
            rem += route["totalLengthM"]
        else:
            return None
    return round(rem)
