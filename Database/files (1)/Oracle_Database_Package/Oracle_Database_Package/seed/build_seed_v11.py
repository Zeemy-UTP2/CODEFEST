"""Generate seed/seed.json (JSON uses camelCase; load_seed.py maps it to the snake_case SQL columns). Distances are computed from the route path, so
cumulative/next distances are always consistent with the coordinates.
ALL COORDINATES ARE APPROXIMATE DEMO VALUES (NOT SURVEYED). Replace with real
approved data before any deployment claim."""
import json, math, pathlib

def haversine_m(a, b):
    R = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(h))

STOPS = {
 "STP-01": ("Main Gate (Demo)",          4.3790, 100.9650),
 "STP-02": ("Academic Block A (Demo)",   4.3825, 100.9690),
 "STP-03": ("Library (Demo)",            4.3850, 100.9715),
 "STP-04": ("Student Centre (Demo)",     4.3870, 100.9740),
 "STP-05": ("Residential Village 1 (Demo)", 4.3900, 100.9770),
 "STP-06": ("Residential Village 2 (Demo)", 4.3880, 100.9800),
 "STP-07": ("Sports Complex (Demo)",     4.3830, 100.9760),
}
ROUTES = {
 "RTE-A": ("Residential Loop (Demo)", "Main Gate to residential villages and back",
           "#E53935", ["STP-01","STP-02","STP-03","STP-04","STP-05","STP-06"]),
 "RTE-B": ("Academic Shuttle (Demo)", "Main Gate, academic area, library and sports complex",
           "#1E88E5", ["STP-01","STP-02","STP-03","STP-07"]),
}

def build():
    stops = [dict(stopId=k, name=v[0], latitude=v[1], longitude=v[2], active=True, dataOrigin="DEMO")
             for k, v in STOPS.items()]
    routes, route_stops, route_points = [], [], []
    for rid, (name, desc, colour, order) in ROUTES.items():
        pts = []   # (lat, lng, stop_id)
        n = len(order)
        for i, sid in enumerate(order):
            a = STOPS[sid]; b = STOPS[order[(i+1) % n]]   # loop closes to first stop
            pts.append((a[1], a[2], sid))
            dlat, dlng = b[1]-a[1], b[2]-a[2]
            pts.append((round((a[1]+b[1])/2 - dlng*0.15, 6), round((a[2]+b[2])/2 + dlat*0.15, 6), None))
        # Distances: round each SEGMENT once, then derive cumulative + total from the
        # rounded segments so that sum(distance_to_next_m) == total_length_m exactly.
        seg = [round(haversine_m(pts[i][:2], pts[(i+1) % len(pts)][:2])) for i in range(len(pts))]
        cum = [0]
        for d in seg:
            cum.append(cum[-1] + d)
        total = cum[-1]
        stop_cum = {p[2]: cum[i] for i, p in enumerate(pts) if p[2]}
        for i, p in enumerate(pts, 1):
            route_points.append(dict(routeId=rid, pointSeq=i, latitude=p[0], longitude=p[1], stopId=p[2]))
        for seq, sid in enumerate(order, 1):
            nxt = stop_cum[order[seq]] if seq < n else total
            route_stops.append(dict(routeId=rid, sequence=seq, stopId=sid,
                                    cumulativeDistanceM=stop_cum[sid],
                                    distanceToNextM=nxt - stop_cum[sid]))
        routes.append(dict(routeId=rid, name=name, description=desc, colourHex=colour,
                           isLoop=True, totalLengthM=total, active=True, dataOrigin="DEMO"))
    buses = [
        dict(busId="BUS-01", label="Demo Bus 1", routeId="RTE-A", serviceState="IN_SERVICE",   dataOrigin="DEMO"),
        dict(busId="BUS-02", label="Demo Bus 2", routeId="RTE-B", serviceState="IN_SERVICE",   dataOrigin="DEMO"),
        dict(busId="BUS-03", label="Demo Bus 3", routeId=None,    serviceState="OUT_OF_SERVICE", dataOrigin="DEMO"),
        dict(busId="BUS-04", label="Demo Bus 4", routeId="RTE-A", serviceState="IN_SERVICE",   dataOrigin="DEMO"),
    ]
    # ageSeconds = age of the timestamp at (re)seed time -> shows each freshness state
    bus_locations = [
        dict(busId="BUS-01", latitude=4.3825, longitude=100.9690, ageSeconds=5,   speedKmh=18.0, accuracyM=6.0, dataSource="SIMULATED"),  # LIVE
        dict(busId="BUS-02", latitude=4.3850, longitude=100.9715, ageSeconds=600, speedKmh=0.0,  accuracyM=8.0, dataSource="SIMULATED"),  # OFFLINE
        dict(busId="BUS-04", latitude=4.3870, longitude=100.9740, ageSeconds=60,  speedKmh=15.0, accuracyM=9.0, dataSource="SIMULATED"),  # STALE
        # BUS-03: deliberately NO location row -> out of service / no data
    ]
    config = [
        ("update_interval_s", 5, "seconds", "Expected interval between GPS updates from the sender"),
        ("stale_after_s", 30, "seconds", "Age above which a location is STALE (not shown as live)"),
        ("offline_after_s", 120, "seconds", "Age above which the bus is treated as OFFLINE"),
        ("max_future_skew_s", 60, "seconds", "Max allowed timestamp ahead of server clock"),
        ("max_jump_speed_kmh", 100, "km/h", "Implied speed between consecutive updates above which an update is rejected"),
        ("default_avg_speed_kmh", 20, "km/h", "Fallback average bus speed for ETA (Wafiy may tune)"),
        ("bbox_min_lat", 4.34, "degrees", "Service-area bounding box (demo value, verify)"),
        ("bbox_max_lat", 4.43, "degrees", "Service-area bounding box (demo value, verify)"),
        ("bbox_min_lng", 100.92, "degrees", "Service-area bounding box (demo value, verify)"),
        ("bbox_max_lng", 101.02, "degrees", "Service-area bounding box (demo value, verify)"),
    ]
    return dict(_meta=dict(note="DEMO/SIMULATED DATA. Coordinates approximate, not surveyed. Not a real live service.",
                           version="1.1"),
                systemConfig=[dict(key=k, value=v, unit=u, description=d) for k, v, u, d in config],
                stops=stops, routes=routes, routeStops=route_stops, routePoints=route_points,
                buses=buses, busLocations=bus_locations)

if __name__ == "__main__":
    out = pathlib.Path(__file__).with_name("seed.json")
    out.write_text(json.dumps(build(), indent=2))
    print("wrote", out)
