"""
Where the data lives. Two interchangeable versions:

  OracleStore - Roy's Oracle database. Validation runs inside the database
                (pkg_bus_tracker.apply_location_update) and status comes from
                his view v_bus_status.
  LocalStore  - an in-memory copy of Roy's demo data, using rules.py (the same
                rules in Python). Used when Oracle is not configured or not
                reachable, so the demo always works.

Both give the API exactly the same data in exactly the same shape.
"""
import threading
from datetime import timezone

import rules
import seed_data


def build_route(route_id, name, description, colour, is_loop, total_length_m, stop_rows, point_rows, stop_names):
    """Puts one route's data into the shape the rest of the code uses."""
    stops = [
        {
            "sequence": seq,
            "stopId": stop_id,
            "name": stop_names.get(stop_id, stop_id),
            "cumulativeDistanceM": cum,
            "distanceToNextM": nxt,
        }
        for seq, stop_id, cum, nxt in sorted(stop_rows)
    ]
    return {
        "route_id": route_id,
        "name": name,
        "description": description,
        "colour": colour,
        "is_loop": bool(is_loop),
        "total_length_m": total_length_m,
        "stops": stops,
        "stop_cum": {s["stopId"]: s["cumulativeDistanceM"] for s in stops},
        "points": [(lat, lng, cum) for _, lat, lng, cum in sorted(point_rows)],
    }


class BaseStore:
    """Everything that is the same for Oracle and local mode."""

    mode = "base"
    notice = ""

    # --- implemented by each store ---
    def config(self): raise NotImplementedError
    def routes(self): raise NotImplementedError          # {route_id: route dict}
    def stops(self): raise NotImplementedError           # {stop_id: (name, lat, lng)}
    def bus_status(self): raise NotImplementedError      # list of status dicts
    def apply_update(self, update): raise NotImplementedError
    def log_reject(self, reason, bus_id=None): raise NotImplementedError
    def reset_demo(self): raise NotImplementedError
    def recent_log(self, limit): raise NotImplementedError

    # --- shared ---
    def routes_json(self):
        return [
            {
                "routeId": r["route_id"],
                "name": r["name"],
                "description": r["description"],
                "colour": r["colour"],
                "isLoop": r["is_loop"],
                "totalLengthM": r["total_length_m"],
                "stops": r["stops"],
                "path": [[lat, lng] for lat, lng, _ in r["points"]],
                "pathCumulativeM": [cum for _, _, cum in r["points"]],
            }
            for r in self.routes().values()
        ]

    def stops_json(self):
        served_by = {}
        for r in self.routes().values():
            for s in r["stops"]:
                served_by.setdefault(s["stopId"], []).append(r["route_id"])
        return [
            {"stopId": sid, "name": name, "latitude": lat, "longitude": lng, "routes": served_by.get(sid, [])}
            for sid, (name, lat, lng) in sorted(self.stops().items())
        ]

    def _eta_speed(self, bus, cfg):
        """Bus's own speed when it is clearly moving, otherwise the configured average."""
        speed = bus.get("speedKmh")
        return speed if speed is not None and speed >= 5 else cfg["default_avg_speed_kmh"]

    def _estimate(self, bus, route, stop_id, cfg):
        """Distance and ETA from one bus to one stop, with an honest reason when unknown."""
        if bus["displayStatus"] not in ("ACTIVE", "STALE"):
            return None, None, "No recent location"
        dist = rules.remaining_distance_m(route, bus["latitude"], bus["longitude"], stop_id, cfg["arrival_radius_m"])
        if dist is None:
            return None, None, "Position not on this route"
        return dist, rules.eta_minutes(dist, self._eta_speed(bus, cfg)), None

    def arrivals(self, stop_id):
        cfg, routes = self.config(), self.routes()
        if stop_id not in self.stops():
            return None
        result = []
        for bus in self.bus_status():
            route = routes.get(bus["routeId"])
            if not route or stop_id not in route["stop_cum"]:
                continue
            dist, eta, why = self._estimate(bus, route, stop_id, cfg)
            result.append({
                "busId": bus["busId"],
                "label": bus["label"],
                "routeId": route["route_id"],
                "routeName": route["name"],
                "routeColour": route["colour"],
                "displayStatus": bus["displayStatus"],
                "freshness": bus["freshness"],
                "ageSeconds": bus["ageSeconds"],
                "remainingDistanceM": dist,
                "etaMinutes": eta,
                "etaIsApproximate": bus["displayStatus"] == "STALE",
                "unavailableReason": why,
            })
        result.sort(key=lambda a: (a["etaMinutes"] is None, a["etaMinutes"] or 0))
        return result

    def next_stops(self, bus_id):
        cfg, routes = self.config(), self.routes()
        bus = next((b for b in self.bus_status() if b["busId"] == bus_id), None)
        if bus is None:
            return None
        route = routes.get(bus["routeId"])
        stops = []
        if route:
            for s in route["stops"]:
                dist, eta, why = self._estimate(bus, route, s["stopId"], cfg)
                stops.append({**s, "remainingDistanceM": dist, "etaMinutes": eta, "unavailableReason": why})
            stops.sort(key=lambda s: (s["remainingDistanceM"] is None, s["remainingDistanceM"] or 0))
        return {"bus": bus, "routeName": route["name"] if route else None, "stops": stops}


def status_row(bus_id, label, route_id, service_state, data_origin, loc, age, cfg):
    """One bus's status in the API's JSON shape (same columns as Roy's v_bus_status)."""
    fresh = rules.freshness(age, cfg)
    return {
        "busId": bus_id,
        "label": label,
        "routeId": route_id,
        "serviceState": service_state,
        "dataOrigin": data_origin,
        "latitude": loc["latitude"] if loc else None,
        "longitude": loc["longitude"] if loc else None,
        "timestamp": rules.to_iso_utc(loc["timestamp"]) if loc else None,
        "receivedAt": rules.to_iso_utc(loc["received_at"]) if loc else None,
        "speedKmh": loc["speed_kmh"] if loc else None,
        "accuracyM": loc["accuracy_m"] if loc else None,
        "dataSource": loc["data_source"] if loc else None,
        "ageSeconds": age,
        "freshness": fresh,
        "displayStatus": rules.display_status(service_state, fresh),
    }


# =====================================================================
# Local mode
# =====================================================================
class LocalStore(BaseStore):
    mode = "local"

    def __init__(self, notice="Oracle not connected - using a local copy of the demo data."):
        self.notice = notice
        self._lock = threading.Lock()
        self._cfg = dict(seed_data.SYSTEM_CONFIG)
        self._stops = dict(seed_data.STOPS)
        names = {sid: v[0] for sid, v in self._stops.items()}
        self._routes = {}
        for rid, (name, desc, colour, is_loop, total) in seed_data.ROUTES.items():
            stop_rows = [(seq, sid, cum, nxt) for r, seq, sid, cum, nxt in seed_data.ROUTE_STOPS if r == rid]
            point_rows = [(seq, lat, lng, cum) for r, seq, lat, lng, _, cum in seed_data.ROUTE_POINTS if r == rid]
            self._routes[rid] = build_route(rid, name, desc, colour, is_loop, total, stop_rows, point_rows, names)
        self._buses = dict(seed_data.BUSES)
        self._locations = {}
        self._log = []
        self.reset_demo()

    def config(self): return self._cfg
    def routes(self): return self._routes
    def stops(self): return self._stops

    def bus_status(self, now=None):
        now = now or rules.utc_now()
        with self._lock:
            rows = []
            for bus_id, (label, route_id, state) in sorted(self._buses.items()):
                loc = self._locations.get(bus_id)
                age = round((now - loc["timestamp"]).total_seconds()) if loc else None
                rows.append(status_row(bus_id, label, route_id, state, "DEMO", loc, age, self._cfg))
            return rows

    def apply_update(self, update, now=None):
        now = now or rules.utc_now()
        with self._lock:
            stored = self._locations.get(update.get("busId"))
            outcome, reason, ts, source = rules.check_update(update, self._cfg, self._buses, stored, now)
            if outcome == "ACCEPT":
                self._locations[update["busId"]] = {
                    "latitude": update["latitude"],
                    "longitude": update["longitude"],
                    "timestamp": ts,
                    "received_at": now,
                    "speed_kmh": update.get("speedKmh"),
                    "accuracy_m": update.get("accuracyM"),
                    "data_source": source,
                }
            self._write_log(update.get("busId"), update.get("latitude"), update.get("longitude"),
                            update.get("timestamp"), update.get("dataSource"), outcome, reason, now)
            return outcome, reason

    def _write_log(self, bus_id, lat, lng, ts, source, outcome, reason, now):
        self._log.append({
            "busId": bus_id, "latitude": lat, "longitude": lng, "timestamp": ts,
            "receivedAt": rules.to_iso_utc(now), "dataSource": source, "outcome": outcome, "reason": reason,
        })
        del self._log[:-500]  # keep the last 500 entries

    def log_reject(self, reason, bus_id=None):
        with self._lock:
            self._write_log(bus_id, None, None, None, None, "REJECT", reason, rules.utc_now())

    def reset_demo(self):
        """Same as pkg_bus_tracker.refresh_demo_locations: demo buses re-timed to 'now'."""
        from datetime import timedelta
        now = rules.utc_now()
        with self._lock:
            self._log.clear()
            self._locations = {
                bus_id: {
                    "latitude": lat, "longitude": lng, "timestamp": now - timedelta(seconds=age),
                    "received_at": now, "speed_kmh": speed, "accuracy_m": acc, "data_source": src,
                }
                for bus_id, (lat, lng, age, speed, acc, src) in seed_data.DEMO_LOCATION_TEMPLATE.items()
            }

    def recent_log(self, limit):
        with self._lock:
            return list(reversed(self._log[-limit:]))


# =====================================================================
# Oracle mode
# =====================================================================
class OracleStore(BaseStore):
    mode = "oracle"
    notice = "Connected to the Oracle database."

    def __init__(self, user, password, dsn, schema):
        import oracledb  # only needed in Oracle mode

        self._schema = schema.upper()
        self._pool = oracledb.create_pool(user=user, password=password, dsn=dsn, min=1, max=4, increment=1)
        self._ref = None  # reference data (routes, stops, config), loaded once
        self._load_reference()

    def _t(self, name):
        return f"{self._schema}.{name}"

    def _query(self, sql, params=None):
        with self._pool.acquire() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, params or {})
                cols = [c[0].lower() for c in cur.description]
                return [dict(zip(cols, row)) for row in cur.fetchall()]

    def _load_reference(self):
        cfg = {r["config_key"]: float(r["config_value"]) for r in
               self._query(f"SELECT config_key, config_value FROM {self._t('system_config')}")}
        stops = {r["stop_id"]: (r["name"], float(r["latitude"]), float(r["longitude"])) for r in
                 self._query(f"SELECT stop_id, name, latitude, longitude FROM {self._t('stops')} WHERE active = 1")}
        names = {sid: v[0] for sid, v in stops.items()}
        stop_rows, point_rows = {}, {}
        for r in self._query(f"SELECT route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m "
                             f"FROM {self._t('route_stops')}"):
            stop_rows.setdefault(r["route_id"], []).append(
                (r["stop_sequence"], r["stop_id"], r["cumulative_distance_m"], r["distance_to_next_m"]))
        for r in self._query(f"SELECT route_id, point_seq, latitude, longitude, cumulative_distance_m "
                             f"FROM {self._t('route_points')}"):
            point_rows.setdefault(r["route_id"], []).append(
                (r["point_seq"], float(r["latitude"]), float(r["longitude"]), r["cumulative_distance_m"]))
        routes = {}
        for r in self._query(f"SELECT route_id, name, description, colour_hex, is_loop, total_length_m "
                             f"FROM {self._t('routes')} WHERE active = 1"):
            rid = r["route_id"]
            routes[rid] = build_route(rid, r["name"], r["description"], r["colour_hex"], r["is_loop"],
                                      r["total_length_m"], stop_rows.get(rid, []), point_rows.get(rid, []), names)
        self._ref = {"cfg": cfg, "stops": stops, "routes": routes}

    def config(self): return self._ref["cfg"]
    def routes(self): return self._ref["routes"]
    def stops(self): return self._ref["stops"]

    def bus_status(self):
        rows = self._query(
            f"SELECT bus_id, label, route_id, service_state, data_origin, latitude, longitude, "
            f"timestamp_iso, received_at_iso, speed_kmh, accuracy_m, data_source, age_seconds, "
            f"data_freshness, display_status FROM {self._t('v_bus_status')} ORDER BY bus_id")
        num = lambda v: float(v) if v is not None else None
        return [
            {
                "busId": r["bus_id"], "label": r["label"], "routeId": r["route_id"],
                "serviceState": r["service_state"], "dataOrigin": r["data_origin"],
                "latitude": num(r["latitude"]), "longitude": num(r["longitude"]),
                "timestamp": r["timestamp_iso"], "receivedAt": r["received_at_iso"],
                "speedKmh": num(r["speed_kmh"]), "accuracyM": num(r["accuracy_m"]),
                "dataSource": r["data_source"],
                "ageSeconds": int(r["age_seconds"]) if r["age_seconds"] is not None else None,
                "freshness": r["data_freshness"], "displayStatus": r["display_status"],
            }
            for r in rows
        ]

    def apply_update(self, update):
        with self._pool.acquire() as conn:
            with conn.cursor() as cur:
                outcome, reason = cur.var(str), cur.var(str)
                cur.callproc(f"{self._schema}.pkg_bus_tracker.apply_location_update", keyword_parameters={
                    "p_bus_id": update.get("busId"),
                    "p_latitude": update.get("latitude"),
                    "p_longitude": update.get("longitude"),
                    "p_timestamp": update.get("timestamp"),
                    "p_outcome": outcome,
                    "p_reason": reason,
                    "p_speed_kmh": update.get("speedKmh"),
                    "p_accuracy_m": update.get("accuracyM"),
                    "p_data_source": update.get("dataSource"),
                })
                return outcome.getvalue(), reason.getvalue()

    def log_reject(self, reason, bus_id=None):
        with self._pool.acquire() as conn:
            with conn.cursor() as cur:
                cur.callproc(f"{self._schema}.pkg_bus_tracker.log_reject",
                             keyword_parameters={"p_reason": reason, "p_bus_id": bus_id})

    def reset_demo(self):
        with self._pool.acquire() as conn:
            with conn.cursor() as cur:
                cur.callproc(f"{self._schema}.pkg_bus_tracker.refresh_demo_locations")

    def recent_log(self, limit):
        rows = self._query(
            f"SELECT bus_id, latitude, longitude, location_timestamp, received_at, data_source, outcome, reason_code "
            f"FROM {self._t('location_log')} ORDER BY log_id DESC FETCH FIRST :n ROWS ONLY", {"n": limit})
        return [
            {
                "busId": r["bus_id"], "latitude": r["latitude"], "longitude": r["longitude"],
                "timestamp": r["location_timestamp"],
                "receivedAt": rules.to_iso_utc(r["received_at"].replace(tzinfo=timezone.utc)) if r["received_at"] else None,
                "dataSource": r["data_source"], "outcome": r["outcome"], "reason": r["reason_code"],
            }
            for r in rows
        ]


def open_store(settings, log=print):
    """Oracle if it is configured and reachable, otherwise the local demo copy."""
    if not settings.get("ORACLE_DSN"):
        return LocalStore()
    try:
        store = OracleStore(settings.get("ORACLE_USER", "bus_app"), settings.get("ORACLE_PASSWORD", ""),
                            settings["ORACLE_DSN"], settings.get("ORACLE_SCHEMA", "BUS_OWNER"))
        log(f"Connected to Oracle at {settings['ORACLE_DSN']}")
        return store
    except Exception as error:  # missing driver, wrong password, database not running...
        log(f"WARNING: could not use Oracle ({error}). Falling back to local demo data.")
        return LocalStore(notice=f"Oracle connection failed - using local demo data. ({type(error).__name__})")
