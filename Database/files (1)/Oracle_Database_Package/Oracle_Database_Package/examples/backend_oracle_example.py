"""Example: how the BACKEND (Hazeem) talks to the Oracle database.   NOT part of the database itself.

    pip install oracledb            # 'thin' mode: no Oracle Client install needed
    set BUS_DB_USER=bus_app         # (Windows)   export BUS_DB_USER=bus_app  (macOS/Linux)
    set BUS_DB_PASSWORD=...         # NEVER commit this. Keep it in an .env / environment variable.
    set BUS_DB_DSN=localhost:1521/XEPDB1

The student app (Flutter) calls the backend over HTTP; it never gets a database login.
Wire these two functions behind your endpoints, e.g.
    POST /locations   -> submit_location(json_body)
    GET  /buses       -> list_buses()
Status: written against the python-oracledb API from documentation; run it once against the demo
database (after install_all.sql) and adjust if your setup differs.
"""
import math
import os

import oracledb

pool = oracledb.create_pool(
    user=os.environ["BUS_DB_USER"],
    password=os.environ["BUS_DB_PASSWORD"],
    dsn=os.environ.get("BUS_DB_DSN", "localhost:1521/XEPDB1"),
    min=1, max=4,
)
SCHEMA = "BUS_OWNER"   # objects live in BUS_OWNER; BUS_APP only has SELECT / EXECUTE on them


def _is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def submit_location(payload):
    """JSON body from the GPS sender -> (outcome, reason_code). Always returns, never raises for bad data."""
    with pool.acquire() as conn:
        cur = conn.cursor()
        cur.execute(f"ALTER SESSION SET CURRENT_SCHEMA = {SCHEMA}")

        # Rules 1 and 3 (JSON level) are checked here, the other rules inside the database.
        if not isinstance(payload, dict):
            cur.callproc("pkg_bus_tracker.log_reject", ["MALFORMED_PAYLOAD"])
            return "REJECT", "MALFORMED_PAYLOAD"
        lat, lng = payload.get("latitude"), payload.get("longitude")
        bad_type = (lat is not None and not _is_number(lat)) or (lng is not None and not _is_number(lng)) \
            or (payload.get("busId") is not None and not isinstance(payload.get("busId"), str))
        if bad_type:
            cur.callproc("pkg_bus_tracker.log_reject", ["BAD_TYPE", str(payload.get("busId"))[:40]])
            return "REJECT", "BAD_TYPE"

        outcome = cur.var(str)
        reason = cur.var(str)
        cur.execute(
            """BEGIN
                 pkg_bus_tracker.apply_location_update(
                   p_bus_id => :bus, p_latitude => :lat, p_longitude => :lng, p_timestamp => :ts,
                   p_outcome => :outcome, p_reason => :reason,
                   p_speed_kmh => :speed, p_accuracy_m => :acc, p_data_source => :src);
               END;""",
            dict(bus=payload.get("busId"), lat=lat, lng=lng, ts=payload.get("timestamp"),
                 outcome=outcome, reason=reason,
                 speed=payload.get("speedKmh"), acc=payload.get("accuracyM"), src=payload.get("dataSource")),
        )
        return outcome.getvalue(), reason.getvalue()


# SQL column -> JSON field name (the camelCase API contract)
JSON_NAMES = {
    "bus_id": "busId", "label": "label", "route_id": "routeId", "service_state": "serviceState",
    "data_origin": "dataOrigin", "latitude": "latitude", "longitude": "longitude",
    "timestamp_iso": "timestamp", "received_at_iso": "receivedAt", "speed_kmh": "speedKmh",
    "accuracy_m": "accuracyM", "data_source": "dataSource", "age_seconds": "ageSeconds",
    "data_freshness": "dataFreshness", "display_status": "displayStatus",
}


def list_buses():
    """All buses with their latest location, freshness and status (view v_bus_status)."""
    with pool.acquire() as conn:
        cur = conn.cursor()
        cols = ", ".join(JSON_NAMES)
        cur.execute(f"SELECT {cols} FROM {SCHEMA}.v_bus_status ORDER BY bus_id")
        names = [JSON_NAMES[d[0].lower()] for d in cur.description]
        return [dict(zip(names, row)) for row in cur.fetchall()]


if __name__ == "__main__":
    # quick smoke test after install_all.sql
    for bus in list_buses():
        print(bus["busId"], bus["displayStatus"], bus["dataFreshness"], bus["ageSeconds"])
