"""
Roy's test cases from database/05_tests.sql, run against the Python rules.
Proves local mode behaves exactly like the Oracle package.

Run:  py test_rules.py
"""
from datetime import datetime, timezone

import rules
from store import LocalStore

NOW = datetime(2026, 10, 4, 8, 30, 0, tzinfo=timezone.utc)  # fixed test clock
passed = failed = 0


def ok(case_id, description, condition):
    global passed, failed
    if condition:
        passed += 1
        print(f"PASS {case_id:<8} {description}")
    else:
        failed += 1
        print(f"FAIL {case_id:<8} {description}")


def fresh_store():
    """BUS-01 stored at 4.3825, 100.969 at 08:29:55 (5 s before NOW), like reset_bus in the SQL."""
    store = LocalStore()
    store._locations["BUS-01"] = {
        "latitude": 4.3825, "longitude": 100.969, "timestamp": datetime(2026, 10, 4, 8, 29, 55, tzinfo=timezone.utc),
        "received_at": NOW, "speed_kmh": 18, "accuracy_m": 6, "data_source": "SIMULATED",
    }
    return store


def update(case_id, description, expected, bus, lat, lng, ts, source=None, speed=None, store=None):
    store = store or fresh_store()
    result = store.apply_update({"busId": bus, "latitude": lat, "longitude": lng, "timestamp": ts,
                                 "dataSource": source, "speedKmh": speed}, now=NOW)
    ok(case_id, f"{description} -> {result[0]}/{result[1]}", result == expected)


A = ("ACCEPT", "OK")
print("--- location update validation ---")
update("V01", "valid newer update", A, "BUS-01", 4.3827, 100.9692, "2026-10-04T08:30:00Z")
s = fresh_store(); del s._locations["BUS-04"]
update("V02", "first ever update for a bus", A, "BUS-04", 4.387, 100.974, "2026-10-04T08:30:00Z", store=s)
update("V03", "missing busId", ("REJECT", "MISSING_FIELD"), None, 4.3827, 100.9692, "2026-10-04T08:30:00Z")
update("V04", "missing timestamp", ("REJECT", "MISSING_FIELD"), "BUS-01", 4.3827, 100.9692, None)
update("V05", "null latitude", ("REJECT", "MISSING_FIELD"), "BUS-01", None, 100.9692, "2026-10-04T08:30:00Z")
update("V08", "unknown bus BUS-99", ("REJECT", "UNKNOWN_BUS"), "BUS-99", 4.3827, 100.9692, "2026-10-04T08:30:00Z")
update("V09", "latitude 91", ("REJECT", "OUT_OF_RANGE"), "BUS-01", 91, 100.9692, "2026-10-04T08:30:00Z")
update("V10", "longitude -181", ("REJECT", "OUT_OF_RANGE"), "BUS-01", 4.3827, -181, "2026-10-04T08:30:00Z")
update("V11", "(0,0)", ("REJECT", "OUTSIDE_SERVICE_AREA"), "BUS-01", 0, 0, "2026-10-04T08:30:00Z")
update("V12", "far away (Kuala Lumpur)", ("REJECT", "OUTSIDE_SERVICE_AREA"), "BUS-01", 3.139, 101.6869, "2026-10-04T08:30:00Z")
update("V13", "timestamp 04/10/2026 08:30", ("REJECT", "BAD_TIMESTAMP"), "BUS-01", 4.3827, 100.9692, "04/10/2026 08:30")
update("V14", "timestamp without Z", ("REJECT", "BAD_TIMESTAMP"), "BUS-01", 4.3827, 100.9692, "2026-10-04T08:30:00")
update("V13b", "impossible date 2026-02-30", ("REJECT", "BAD_TIMESTAMP"), "BUS-01", 4.3827, 100.9692, "2026-02-30T08:30:00Z")
update("V13c", "trailing newline in timestamp", ("REJECT", "BAD_TIMESTAMP"), "BUS-01", 4.3827, 100.9692, "2026-10-04T08:30:00Z\n")
update("V15", "10 minutes in the future", ("REJECT", "FUTURE_TIMESTAMP"), "BUS-01", 4.3827, 100.9692, "2026-10-04T08:40:00Z")
update("V16", "30 s in the future (clock skew)", A, "BUS-01", 4.3827, 100.9692, "2026-10-04T08:30:30Z")
update("V17", "same timestamp as stored", ("IGNORE_DUPLICATE", "DUPLICATE_TIMESTAMP"), "BUS-01", 4.3827, 100.9692, "2026-10-04T08:29:55Z")
update("V18", "older than stored", ("IGNORE_OLDER", "OLDER_THAN_STORED"), "BUS-01", 4.3827, 100.9692, "2026-10-04T08:29:50Z")
update("V19", "about 5 km in 10 s", ("REJECT", "IMPLAUSIBLE_JUMP"), "BUS-01", 4.4275, 100.969, "2026-10-04T08:30:05Z")
update("V21", "small GPS jitter under 50 m", A, "BUS-01", 4.38253, 100.96903, "2026-10-04T08:29:56Z")
update("V22", "bad dataSource", ("REJECT", "BAD_OPTIONAL_FIELD"), "BUS-01", 4.3827, 100.9692, "2026-10-04T08:30:00Z", source="GPS")
update("V23", "negative speed", ("REJECT", "BAD_OPTIONAL_FIELD"), "BUS-01", 4.3827, 100.9692, "2026-10-04T08:30:00Z", speed=-1)
update("V24", "dataSource omitted", A, "BUS-01", 4.3827, 100.9692, "2026-10-04T08:30:00Z", speed=18)

s = fresh_store()
s.apply_update({"busId": "BUS-01", "latitude": 91, "longitude": 100.9, "timestamp": "2026-10-04T08:30:00Z"}, now=NOW)
s.apply_update({"busId": "BUS-01", "latitude": 4.3827, "longitude": 100.9692, "timestamp": "2026-10-04T08:29:50Z"}, now=NOW)
loc = s._locations["BUS-01"]
ok("V26", "rejected + older updates leave the stored location untouched",
   loc["latitude"] == 4.3825 and rules.to_iso_utc(loc["timestamp"]) == "2026-10-04T08:29:55Z")

print("--- freshness, status, ETA, time helpers ---")
cfg = LocalStore().config()
for case_id, age, expected in [("F01", 5, "LIVE"), ("F02", 30, "LIVE"), ("F03", 31, "STALE"), ("F04", 120, "STALE"),
                               ("F05", 121, "OFFLINE"), ("F06", 86400, "OFFLINE"), ("F07", None, "UNAVAILABLE")]:
    ok(case_id, f"age {age} -> {expected}", rules.freshness(age, cfg) == expected)
for case_id, state, fresh, expected in [("S01", "OUT_OF_SERVICE", "LIVE", "NOT_IN_SERVICE"),
                                        ("S02", "OUT_OF_SERVICE", "UNAVAILABLE", "NOT_IN_SERVICE"),
                                        ("S03", "IN_SERVICE", "LIVE", "ACTIVE"), ("S04", "IN_SERVICE", "STALE", "STALE"),
                                        ("S05", "IN_SERVICE", "OFFLINE", "OFFLINE"), ("S06", "IN_SERVICE", "UNAVAILABLE", "NO_DATA")]:
    ok(case_id, f"{state} x {fresh}", rules.display_status(state, fresh) == expected)
ok("E01", "1000 m at 20 km/h = 3.0 min", rules.eta_minutes(1000, 20) == 3.0)
ok("E02", "zero speed -> None", rules.eta_minutes(1000, 0) is None)
ok("E03", "negative speed -> None", rules.eta_minutes(1000, -5) is None)
ok("E04", "missing speed -> None", rules.eta_minutes(1000, None) is None)
ok("E05", "missing distance -> None", rules.eta_minutes(None, 20) is None)
ok("E06", "negative distance -> None", rules.eta_minutes(-1, 20) is None)
ok("E07", "0 m -> 0.0", rules.eta_minutes(0, 20) == 0)
ok("P01", "parse_iso_utc valid", rules.parse_iso_utc("2026-10-04T08:30:00Z") == NOW)
ok("P02", "to_iso_utc round trip", rules.to_iso_utc(NOW) == "2026-10-04T08:30:00Z")
ok("P03", "haversine 0.045 deg latitude ~ 5003.8 m", abs(rules.haversine_m(4.3825, 100.969, 4.4275, 100.969) - 5003.77) < 1)

print("--- route-aware distance ---")
routes, radius = LocalStore().routes(), cfg["arrival_radius_m"]
rd = lambda route, lat, lng, stop: rules.remaining_distance_m(routes.get(route), lat, lng, stop, radius)
ok("R01", "loop wrap-around: STP-06 -> STP-01 = 2027 m", rd("RTE-A", 4.388, 100.98, "STP-01") == 2027)
ok("R02", "bus before stop: STP-01 -> STP-03 = 1026 m", rd("RTE-A", 4.379, 100.965, "STP-03") == 1026)
ok("R03", "bus at the stop itself = 0", rd("RTE-A", 4.3825, 100.969, "STP-02") == 0)
ok("R04", "next stop: STP-02 -> STP-03 = 410 m", rd("RTE-A", 4.3825, 100.969, "STP-03") == 410)
ok("R07", "10 m past STP-02 counts as arrived (0)", rd("RTE-A", 4.38254375, 100.96908125, "STP-02") == 0)
ok("R08", "stop not on this route -> None", rd("RTE-A", 4.379, 100.965, "STP-07") is None)
ok("R10", "unknown route -> None", rd("RTE-Z", 4.379, 100.965, "STP-01") is None)
from store import build_route
temp = build_route("RTE-T", "Temp", "", "#000000", 0, 616, [(1, "STP-01", 0, 616), (2, "STP-02", 616, None)],
                   [(1, 4.379, 100.965, 0), (2, 4.3825, 100.969, 616)], {})
ok("R05", "non-loop bus already past the stop -> None", rules.remaining_distance_m(temp, 4.3825, 100.969, "STP-01", radius) is None)
ok("R06", "non-loop bus before the stop = 616 m", rules.remaining_distance_m(temp, 4.379, 100.965, "STP-02", radius) == 616)

print("--- demo data and status ---")
st = {b["busId"]: b for b in LocalStore().bus_status()}
ok("T-VIEW1", "BUS-01 ACTIVE / LIVE", st["BUS-01"]["displayStatus"] == "ACTIVE" and st["BUS-01"]["freshness"] == "LIVE")
ok("T-VIEW2", "BUS-02 OFFLINE", st["BUS-02"]["displayStatus"] == "OFFLINE")
ok("T-VIEW3", "BUS-03 NOT_IN_SERVICE / UNAVAILABLE", st["BUS-03"]["displayStatus"] == "NOT_IN_SERVICE"
   and st["BUS-03"]["freshness"] == "UNAVAILABLE" and st["BUS-03"]["ageSeconds"] is None)
ok("T-VIEW4", "BUS-04 STALE", st["BUS-04"]["displayStatus"] == "STALE")
ok("T-SEED2", "route totals equal the sum of segment distances",
   all(r["total_length_m"] == sum(s["distanceToNextM"] for s in r["stops"]) for r in routes.values()))

print("=" * 53)
print(f"{passed} passed, {failed} failure(s)")
raise SystemExit(1 if failed else 0)
