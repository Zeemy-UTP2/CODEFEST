"""
Business rules - a Python copy of Roy's Oracle package pkg_bus_tracker (v1.2).

The SAME rules, in the SAME order, with the SAME reason codes, so the app
behaves identically whether it runs on Oracle or on the local demo data.
test_rules.py runs Roy's test cases (05_tests.sql) against this file.
"""
import math
import re
from datetime import datetime, timezone

EARTH_RADIUS_M = 6371000
ISO_UTC = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")


def round_half_up(value, digits=0):
    """Rounds like Oracle's ROUND (0.5 goes away from zero). Python's round() does not."""
    factor = 10 ** digits
    return math.copysign(math.floor(abs(value) * factor + 0.5) / factor, value)


# ---------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------
def utc_now():
    return datetime.now(timezone.utc).replace(microsecond=0)


def parse_iso_utc(text):
    """Strict 'YYYY-MM-DDTHH:MM:SSZ' -> datetime (UTC). None if not valid."""
    if not isinstance(text, str) or len(text) != 20 or not ISO_UTC.fullmatch(text):
        return None
    try:
        return datetime.strptime(text[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError:  # impossible date such as 2026-02-30
        return None


def to_iso_utc(moment):
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if moment else None


# ---------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------
def haversine_m(lat1, lng1, lat2, lng2):
    if None in (lat1, lng1, lat2, lng2):
        return None
    rad = math.pi / 180
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1 * rad) * math.cos(lat2 * rad) * math.sin(dlng / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(min(1, a)))


def _segments(route):
    """Yields (lat1, lng1, cum1, lat2, lng2, cum2) for each piece of the route path."""
    points = route["points"]  # [(lat, lng, cumulative_m), ...] in order
    for i, (lat1, lng1, c1) in enumerate(points):
        if i + 1 < len(points):
            lat2, lng2, c2 = points[i + 1]
        elif route["is_loop"]:  # closing piece back to the first point
            lat2, lng2, c2 = points[0][0], points[0][1], route["total_length_m"]
        else:
            continue
        yield lat1, lng1, c1, lat2, lng2, c2


def distance_along_route(route, latitude, longitude):
    """Projects a position onto the route path. Returns metres from point 1, or None."""
    if not route or not route["points"] or latitude is None or longitude is None:
        return None
    k = EARTH_RADIUS_M * math.pi / 180  # metres per degree
    best_d = best_cum = None
    for lat1, lng1, c1, lat2, lng2, c2 in _segments(route):
        cos_l = math.cos(lat1 * math.pi / 180)
        sx, sy = (lng2 - lng1) * k * cos_l, (lat2 - lat1) * k
        px, py = (longitude - lng1) * k * cos_l, (latitude - lat1) * k
        length2 = sx * sx + sy * sy
        t = 0 if length2 == 0 else max(0, min(1, (px * sx + py * sy) / length2))
        d = math.hypot(px - t * sx, py - t * sy)
        if best_d is None or d < best_d:
            best_d, best_cum = d, c1 + t * (c2 - c1)
    return best_cum


def point_at_distance(route, distance_m):
    """The (lat, lng) at a given distance along the route path (used by the simulator)."""
    total = route["total_length_m"]
    if route["is_loop"]:
        distance_m %= total
    for lat1, lng1, c1, lat2, lng2, c2 in _segments(route):
        if c1 <= distance_m <= c2:
            t = 0 if c2 == c1 else (distance_m - c1) / (c2 - c1)
            return lat1 + t * (lat2 - lat1), lng1 + t * (lng2 - lng1)
    last = route["points"][-1]
    return last[0], last[1]


def remaining_distance_m(route, latitude, longitude, stop_id, arrival_radius_m):
    """Metres still to travel along the route from a position to a stop. None if unknown."""
    if not route or stop_id not in route["stop_cum"]:
        return None
    bus_cum = distance_along_route(route, latitude, longitude)
    if bus_cum is None:
        return None
    remaining = route["stop_cum"][stop_id] - bus_cum
    if remaining < 0:
        if -remaining <= arrival_radius_m:
            return 0  # just passed / standing at the stop
        if route["is_loop"]:
            remaining += route["total_length_m"]  # wrap around the loop
        else:
            return None  # non-loop bus already past the stop
    return int(round_half_up(remaining))


# ---------------------------------------------------------------------
# Freshness, status, ETA
# ---------------------------------------------------------------------
def freshness(age_seconds, cfg):
    if age_seconds is None:
        return "UNAVAILABLE"
    if age_seconds <= cfg["stale_after_s"]:
        return "LIVE"
    if age_seconds <= cfg["offline_after_s"]:
        return "STALE"
    return "OFFLINE"


def display_status(service_state, fresh):
    if service_state == "OUT_OF_SERVICE":
        return "NOT_IN_SERVICE"
    return {"LIVE": "ACTIVE", "STALE": "STALE", "OFFLINE": "OFFLINE"}.get(fresh, "NO_DATA")


def eta_minutes(distance_m, speed_kmh):
    if distance_m is None or distance_m < 0 or speed_kmh is None or speed_kmh <= 0:
        return None
    return round_half_up(distance_m / (speed_kmh * 1000 / 60), 1)


# ---------------------------------------------------------------------
# Location update validation (rules 2-11, same order as the package)
# ---------------------------------------------------------------------
def check_update(update, cfg, known_buses, stored, now):
    """
    update : dict with busId, latitude, longitude, timestamp, speedKmh, accuracyM, dataSource
    stored : the bus's current stored location dict, or None
    Returns (outcome, reason, parsed_timestamp, data_source).
    """
    bus_id, lat, lng, ts_text = (update.get(k) for k in ("busId", "latitude", "longitude", "timestamp"))
    speed, accuracy = update.get("speedKmh"), update.get("accuracyM")

    if bus_id is None or lat is None or lng is None or ts_text is None or bus_id == "":
        return "REJECT", "MISSING_FIELD", None, None

    source = update.get("dataSource") or "SIMULATED"
    if (source not in ("LIVE", "MANUAL", "SIMULATED")
            or (speed is not None and speed < 0) or (accuracy is not None and accuracy < 0)):
        return "REJECT", "BAD_OPTIONAL_FIELD", None, None

    if bus_id not in known_buses:
        return "REJECT", "UNKNOWN_BUS", None, None

    if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        return "REJECT", "OUT_OF_RANGE", None, None

    if not (cfg["bbox_min_lat"] <= lat <= cfg["bbox_max_lat"]
            and cfg["bbox_min_lng"] <= lng <= cfg["bbox_max_lng"]):
        return "REJECT", "OUTSIDE_SERVICE_AREA", None, None

    ts = parse_iso_utc(ts_text)
    if ts is None:
        return "REJECT", "BAD_TIMESTAMP", None, None

    if (ts - now).total_seconds() > cfg["max_future_skew_s"]:
        return "REJECT", "FUTURE_TIMESTAMP", None, None

    if stored:
        if ts == stored["timestamp"]:
            return "IGNORE_DUPLICATE", "DUPLICATE_TIMESTAMP", None, None
        if ts < stored["timestamp"]:
            return "IGNORE_OLDER", "OLDER_THAN_STORED", None, None
        dist = haversine_m(stored["latitude"], stored["longitude"], lat, lng)
        seconds = (ts - stored["timestamp"]).total_seconds()
        if dist >= 50 and seconds > 0 and (dist / seconds) * 3.6 > cfg["max_jump_speed_kmh"]:
            return "REJECT", "IMPLAUSIBLE_JUMP", None, None

    return "ACCEPT", "OK", ts, source
