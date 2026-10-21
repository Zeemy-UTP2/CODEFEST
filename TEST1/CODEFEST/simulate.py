"""
Bus simulator - drives demo buses along their routes by sending GPS updates
to the API, exactly like a real GPS sender would. Every update is marked
dataSource = SIMULATED, so it is never presented as a real bus.

Run (in a SECOND terminal, while the API is running):
    py simulate.py                       # BUS-01 around its route
    py simulate.py --buses BUS-01,BUS-02 # several buses
    py simulate.py --speed 40            # faster, for a short video
Stop with Ctrl+C.
"""
import argparse
import time

import requests

import rules


def main():
    parser = argparse.ArgumentParser(description="Simulate buses moving along their routes.")
    parser.add_argument("--api", default="http://127.0.0.1:8000", help="API address")
    parser.add_argument("--buses", default="BUS-01", help="comma-separated bus IDs")
    parser.add_argument("--speed", type=float, default=25, help="bus speed in km/h (keep under 100)")
    parser.add_argument("--interval", type=float, default=3, help="seconds between updates (at least 1)")
    args = parser.parse_args()
    interval = max(1.0, args.interval)

    routes = {r["routeId"]: {
        "route_id": r["routeId"], "is_loop": r["isLoop"], "total_length_m": r["totalLengthM"],
        "points": [(lat, lng, cum) for (lat, lng), cum in zip(r["path"], r["pathCumulativeM"])],
    } for r in requests.get(f"{args.api}/api/routes", timeout=10).json()}

    buses = {b["busId"]: b for b in requests.get(f"{args.api}/api/buses", timeout=10).json()}
    driving = {}
    for bus_id in [b.strip() for b in args.buses.split(",") if b.strip()]:
        bus = buses.get(bus_id)
        if not bus or not bus["routeId"]:
            print(f"Skipping {bus_id}: unknown bus or no route assigned")
            continue
        route = routes[bus["routeId"]]
        start = rules.distance_along_route(route, bus["latitude"], bus["longitude"]) if bus["latitude"] else 0
        driving[bus_id] = {"route": route, "distance": start or 0}
        print(f"{bus_id}: driving {bus['routeId']} at {args.speed} km/h from {round(start or 0)} m")

    if not driving:
        return
    metres_per_tick = args.speed * 1000 / 3600 * interval
    print("Sending updates - press Ctrl+C to stop.\n")
    while True:
        tick_started = time.time()
        timestamp = rules.to_iso_utc(rules.utc_now())
        for bus_id, d in driving.items():
            d["distance"] += metres_per_tick
            lat, lng = rules.point_at_distance(d["route"], d["distance"])
            try:
                reply = requests.post(f"{args.api}/api/locations", timeout=5, json={
                    "busId": bus_id, "latitude": round(lat, 7), "longitude": round(lng, 7),
                    "timestamp": timestamp, "speedKmh": args.speed, "accuracyM": 5, "dataSource": "SIMULATED",
                }).json()
                print(f"{timestamp} {bus_id} {lat:.5f},{lng:.5f} -> {reply['outcome']}/{reply['reason']}")
            except requests.RequestException as error:
                print(f"{timestamp} {bus_id}: API not reachable ({error.__class__.__name__}) - is it running?")
        time.sleep(max(0, interval - (time.time() - tick_started)))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nSimulator stopped.")
