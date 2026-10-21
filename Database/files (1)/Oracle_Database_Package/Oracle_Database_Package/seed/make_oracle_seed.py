"""Turn seed/seed.json into oracle/03_seed.sql (plain INSERT statements).

Usage (from the project folder):
    python3 seed/build_seed.py          # (re)generate seed/seed.json from the data block
    python3 seed/make_oracle_seed.py    # write oracle/03_seed.sql
    -> then run oracle/03_seed.sql in Oracle (or run install_all.sql)

seed.json stays the single, safe, non-sensitive master copy of the demo data.
JSON uses camelCase; Oracle columns use snake_case; this script does the mapping.
ALL DATA IS DEMO / SIMULATED (coordinates approximate, not surveyed).
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
SEED = HERE / "seed.json"
OUT = HERE.parent / "oracle" / "03_seed.sql"


def lit(v):
    """Python value -> Oracle SQL literal."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("'", "''") + "'"


def insert(table, cols, row):
    vals = ", ".join(lit(row[c]) for c in cols)
    return f"INSERT INTO {table} ({', '.join(c for c in cols)}) VALUES ({vals});"


def build(seed):
    out = []
    add = out.append
    meta = seed["_meta"]
    add("-- =====================================================================")
    add("-- Smart Campus Bus Tracker | Oracle edition | 03_seed.sql  (GENERATED)")
    add(f"-- Source: seed/seed.json v{meta['version']}  -  do not edit by hand;")
    add("-- change seed/build_seed.py and run seed/make_oracle_seed.py instead.")
    add(f"-- {meta['note']}")
    add("-- =====================================================================")
    add("SET DEFINE OFF")
    add("")

    # (table, [(sql_column, json_key)], seed list)
    spec = [
        ("system_config", [("config_key", "key"), ("config_value", "value"),
                           ("unit", "unit"), ("description", "description")], "systemConfig"),
        ("stops", [("stop_id", "stopId"), ("name", "name"), ("latitude", "latitude"),
                   ("longitude", "longitude"), ("active", "active"), ("data_origin", "dataOrigin")], "stops"),
        ("routes", [("route_id", "routeId"), ("name", "name"), ("description", "description"),
                    ("colour_hex", "colourHex"), ("is_loop", "isLoop"), ("total_length_m", "totalLengthM"),
                    ("active", "active"), ("data_origin", "dataOrigin")], "routes"),
        ("route_stops", [("route_id", "routeId"), ("stop_sequence", "sequence"), ("stop_id", "stopId"),
                         ("cumulative_distance_m", "cumulativeDistanceM"),
                         ("distance_to_next_m", "distanceToNextM")], "routeStops"),
        ("route_points", [("route_id", "routeId"), ("point_seq", "pointSeq"), ("latitude", "latitude"),
                          ("longitude", "longitude"), ("stop_id", "stopId"),
                          ("cumulative_distance_m", "cumulativeDistanceM")], "routePoints"),
        ("buses", [("bus_id", "busId"), ("label", "label"), ("route_id", "routeId"),
                   ("service_state", "serviceState"), ("data_origin", "dataOrigin")], "buses"),
        ("demo_location_template", [("bus_id", "busId"), ("latitude", "latitude"), ("longitude", "longitude"),
                                    ("age_seconds", "ageSeconds"), ("speed_kmh", "speedKmh"),
                                    ("accuracy_m", "accuracyM"), ("data_source", "dataSource")], "busLocations"),
    ]
    for table, mapping, key in spec:
        add(f"-- {table} ({len(seed[key])} rows)")
        for r in seed[key]:
            row = {sql: r[js] for sql, js in mapping}
            add(insert(table, [sql for sql, _ in mapping], row))
        add("")

    add("COMMIT;")
    add("")
    add("-- Turn the demo ages (5 s / 60 s / 600 s) into real timestamps relative to NOW.")
    add("BEGIN")
    add("  pkg_bus_tracker.refresh_demo_locations;")
    add("END;")
    add("/")
    add("")
    add("PROMPT 03_seed.sql done (demo data loaded, locations re-timed to now).")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    seed = json.loads(SEED.read_text())
    OUT.write_text(build(seed))
    n = sum(len(seed[k]) for k in ["systemConfig", "stops", "routes", "routeStops",
                                   "routePoints", "buses", "busLocations"])
    print(f"wrote {OUT}  ({n} INSERT statements)")
