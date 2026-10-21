"""Runs without Oracle:  python3 tests/test_data_quality.py
Proves (1) the reference rules (V/F/S/E/R cases) and (2) the seed data invariants.
The same cases exist for the database in oracle/05_tests.sql."""
import json
import pathlib
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import data_quality as dq  # noqa: E402

NOW = datetime(2026, 10, 4, 8, 30, 0, tzinfo=timezone.utc)
BUSES = {"BUS-01", "BUS-02", "BUS-03", "BUS-04"}
STORED = {"latitude": 4.3825, "longitude": 100.969, "timestamp": "2026-10-04T08:29:55Z"}
passed = failed = 0


def check(case, desc, got, expected):
    global passed, failed
    ok = got == expected
    passed += ok
    failed += (not ok)
    print(("PASS " if ok else "FAIL ") + f"{case:5} {desc}" + ("" if ok else f"   got={got!r} expected={expected!r}"))


def upd(**kw):
    p = dict(busId="BUS-01", latitude=4.3827, longitude=100.9692, timestamp="2026-10-04T08:30:00Z")
    p.update(kw)
    return {k: v for k, v in p.items() if v != "__drop__"}


def val(payload, stored=STORED):
    return dq.validate_location_update(payload, stored, BUSES, NOW)


# ---------------- 6.1 location update validation ----------------
check("V01", "valid newer update", val(upd()), ("ACCEPT", "OK"))
check("V02", "first ever update for a bus", val(upd(), stored=None), ("ACCEPT", "OK"))
check("V03", "missing busId", val(upd(busId="__drop__")), ("REJECT", "MISSING_FIELD"))
check("V04", "missing timestamp", val(upd(timestamp="__drop__")), ("REJECT", "MISSING_FIELD"))
check("V05", "null latitude", val(upd(latitude=None)), ("REJECT", "MISSING_FIELD"))
check("V06", 'latitude as string "4.38"', val(upd(latitude="4.38")), ("REJECT", "BAD_TYPE"))
check("V07", "latitude NaN", val(upd(latitude=float("nan"))), ("REJECT", "BAD_TYPE"))
check("V08", "unknown bus BUS-99", val(upd(busId="BUS-99")), ("REJECT", "UNKNOWN_BUS"))
check("V09", "latitude 91", val(upd(latitude=91)), ("REJECT", "OUT_OF_RANGE"))
check("V10", "longitude -181", val(upd(longitude=-181)), ("REJECT", "OUT_OF_RANGE"))
check("V11", "(0,0)", val(upd(latitude=0, longitude=0)), ("REJECT", "OUTSIDE_SERVICE_AREA"))
check("V12", "Kuala Lumpur", val(upd(latitude=3.139, longitude=101.6869)), ("REJECT", "OUTSIDE_SERVICE_AREA"))
check("V13", "timestamp 04/10/2026 08:30", val(upd(timestamp="04/10/2026 08:30")), ("REJECT", "BAD_TIMESTAMP"))
check("V14", "timestamp without Z", val(upd(timestamp="2026-10-04T08:30:00")), ("REJECT", "BAD_TIMESTAMP"))
check("V13b", "impossible date 2026-02-30", val(upd(timestamp="2026-02-30T08:30:00Z")), ("REJECT", "BAD_TIMESTAMP"))
check("V15", "10 minutes in the future", val(upd(timestamp="2026-10-04T08:40:00Z")), ("REJECT", "FUTURE_TIMESTAMP"))
check("V16", "30 s in the future (clock skew)", val(upd(timestamp="2026-10-04T08:30:30Z")), ("ACCEPT", "OK"))
check("V17", "same timestamp as stored", val(upd(timestamp="2026-10-04T08:29:55Z")), ("IGNORE_DUPLICATE", "DUPLICATE_TIMESTAMP"))
check("V18", "older than stored", val(upd(timestamp="2026-10-04T08:29:50Z")), ("IGNORE_OLDER", "OLDER_THAN_STORED"))
check("V19", "about 5 km in 10 s", val(upd(latitude=4.4275, timestamp="2026-10-04T08:30:05Z")), ("REJECT", "IMPLAUSIBLE_JUMP"))
check("V20", "payload is a string", val("hello"), ("REJECT", "MALFORMED_PAYLOAD"))
check("V21", "small GPS jitter under 50 m", val(upd(latitude=4.38253, longitude=100.96903, timestamp="2026-10-04T08:29:56Z")), ("ACCEPT", "OK"))
check("V22", "bad dataSource", val(upd(dataSource="GPS")), ("REJECT", "BAD_OPTIONAL_FIELD"))
check("V23", "negative speed", val(upd(speedKmh=-1)), ("REJECT", "BAD_OPTIONAL_FIELD"))
check("V24", "dataSource omitted defaults to SIMULATED (accepted)", val(upd(speedKmh=18.0, accuracyM=6.0)), ("ACCEPT", "OK"))

# ---------------- 6.2 freshness, status, ETA ----------------
for case, age, exp in [("F01", 5, "LIVE"), ("F02", 30, "LIVE"), ("F03", 31, "STALE"),
                       ("F04", 120, "STALE"), ("F05", 121, "OFFLINE"), ("F06", 86400, "OFFLINE"),
                       ("F07", None, "UNAVAILABLE")]:
    check(case, f"age {age}", dq.freshness(age), exp)
check("F08", "garbage timestamp has no age", dq.freshness(None if dq.parse_iso_utc("garbage") is None else 1), "UNAVAILABLE")
for case, st, fr, exp in [("S01", "OUT_OF_SERVICE", "LIVE", "NOT_IN_SERVICE"), ("S02", "OUT_OF_SERVICE", "UNAVAILABLE", "NOT_IN_SERVICE"),
                          ("S03", "IN_SERVICE", "LIVE", "ACTIVE"), ("S04", "IN_SERVICE", "STALE", "STALE"),
                          ("S05", "IN_SERVICE", "OFFLINE", "OFFLINE"), ("S06", "IN_SERVICE", "UNAVAILABLE", "NO_DATA")]:
    check(case, f"{st} x {fr}", dq.display_status(st, fr), exp)
check("E01", "1000 m at 20 km/h", dq.eta_minutes(1000, 20), 3.0)
check("E02", "zero speed", dq.eta_minutes(1000, 0), None)
check("E03", "negative speed", dq.eta_minutes(1000, -5), None)
check("E04", "missing speed", dq.eta_minutes(1000, None), None)
check("E05", "missing distance", dq.eta_minutes(None, 20), None)
check("E06", "negative distance", dq.eta_minutes(-1, 20), None)
check("E07", "0 m", dq.eta_minutes(0, 20), 0.0)

# ---------------- seed data + route-aware distance ----------------
seed = json.loads((ROOT / "seed" / "seed.json").read_text())
cfg = {c["key"]: c["value"] for c in seed["systemConfig"]}
check("C01", "seed config equals reference defaults", cfg, dq.DEFAULT_CONFIG)


def route_data(rid):
    r = next(x for x in seed["routes"] if x["routeId"] == rid)
    pts = sorted([p for p in seed["routePoints"] if p["routeId"] == rid], key=lambda p: p["pointSeq"])
    rs = sorted([s for s in seed["routeStops"] if s["routeId"] == rid], key=lambda s: s["sequence"])
    return r, pts, rs


stopxy = {s["stopId"]: (s["latitude"], s["longitude"]) for s in seed["stops"]}
rA, pA, sA = route_data("RTE-A")
rem = lambda stop_at, target, route=(rA, pA, sA): dq.remaining_distance_m(route[0], route[1], route[2], *stopxy[stop_at], target)
check("R01", "loop wrap-around: bus at STP-06 -> STP-01", rem("STP-06", "STP-01"), 2027)
check("R02", "bus before stop: bus at STP-01 -> STP-03", rem("STP-01", "STP-03"), 1026)
check("R03", "bus at the stop itself", rem("STP-02", "STP-02"), 0)
check("R04", "next stop: bus at STP-02 -> STP-03", rem("STP-02", "STP-03"), 410)
nonloop = ({"isLoop": 0, "totalLengthM": 616},
           [{"latitude": 4.379, "longitude": 100.965, "cumulativeDistanceM": 0},
            {"latitude": 4.3825, "longitude": 100.969, "cumulativeDistanceM": 616}],
           [{"stopId": "STP-01", "cumulativeDistanceM": 0}, {"stopId": "STP-02", "cumulativeDistanceM": 616}])
check("R05", "non-loop bus already past the stop", rem("STP-02", "STP-01", nonloop), None)
check("R06", "non-loop bus before the stop", rem("STP-01", "STP-02", nonloop), 616)
# ~10 m past STP-02 along the path counts as arrived (within arrival_radius_m)
check("R07", "10 m past the stop = arrived", dq.remaining_distance_m(rA, pA, sA, 4.38254375, 100.96908125, "STP-02"), 0)
check("R08", "stop not on this route", rem("STP-01", "STP-07"), None)
mid = dq.remaining_distance_m(rA, pA, sA, 4.38254375, 100.96908125, "STP-03")
check("R09", "10 m past STP-02 -> STP-03 is slightly under 410 m", 395 <= mid <= 410, True)

# seed invariants
ok = True
for r in seed["routes"]:
    rid = r["routeId"]
    _, pts, rs = route_data(rid)
    ok &= sum(s["distanceToNextM"] for s in rs) == r["totalLengthM"]
    ok &= [s["sequence"] for s in rs] == list(range(1, len(rs) + 1))
    ok &= all(rs[i + 1]["cumulativeDistanceM"] == rs[i]["cumulativeDistanceM"] + rs[i]["distanceToNextM"] for i in range(len(rs) - 1))
    ok &= rs[0]["cumulativeDistanceM"] == 0
    ok &= [p["pointSeq"] for p in pts] == list(range(1, len(pts) + 1))
    ok &= all(pts[i]["cumulativeDistanceM"] < pts[i + 1]["cumulativeDistanceM"] for i in range(len(pts) - 1))
    ok &= pts[-1]["cumulativeDistanceM"] < r["totalLengthM"]
    sc = {s["stopId"]: s["cumulativeDistanceM"] for s in rs}
    ok &= all(sc[p["stopId"]] == p["cumulativeDistanceM"] for p in pts if p["stopId"])
    ok &= {p["stopId"] for p in pts if p["stopId"]} == set(sc)
check("D01", "route totals, sequences, cumulative distances, points consistent", ok, True)
check("D02", "every stop inside the service-area box",
      all(cfg["bbox_min_lat"] <= s["latitude"] <= cfg["bbox_max_lat"] and cfg["bbox_min_lng"] <= s["longitude"] <= cfg["bbox_max_lng"] for s in seed["stops"]), True)
check("D03", "everything labelled DEMO / SIMULATED",
      all(x["dataOrigin"] == "DEMO" for k in ("stops", "routes", "buses") for x in seed[k])
      and all(b["dataSource"] == "SIMULATED" for b in seed["busLocations"]), True)
check("D04", "row counts 7/2/10/20/4/3/11",
      [len(seed[k]) for k in ("stops", "routes", "routeStops", "routePoints", "buses", "busLocations", "systemConfig")], [7, 2, 10, 20, 4, 3, 11])
check("D05", "demo freshness: ages 5/600/60 -> LIVE/OFFLINE/STALE",
      [dq.freshness(b["ageSeconds"]) for b in seed["busLocations"]], ["LIVE", "OFFLINE", "STALE"])
check("D06", "BUS-03 intentionally has no location", {b["busId"] for b in seed["buses"]} - {b["busId"] for b in seed["busLocations"]}, {"BUS-03"})

print(f"\n{passed} passed, {failed} failure(s)")
sys.exit(1 if failed else 0)
