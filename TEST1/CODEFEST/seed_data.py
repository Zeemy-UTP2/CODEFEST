"""
Demo data - a copy of Roy's database/03_seed.sql (seed v1.2).

Used only in LOCAL mode, when the Oracle database is not connected.
DEMO/SIMULATED DATA. Coordinates approximate, not surveyed. Not a real live service.
If Roy changes 03_seed.sql, update this file to match.
"""

SYSTEM_CONFIG = {
    "update_interval_s": 5,
    "stale_after_s": 30,
    "offline_after_s": 120,
    "max_future_skew_s": 60,
    "max_jump_speed_kmh": 100,
    "default_avg_speed_kmh": 20,
    "arrival_radius_m": 30,
    "bbox_min_lat": 4.34,
    "bbox_max_lat": 4.43,
    "bbox_min_lng": 100.92,
    "bbox_max_lng": 101.02,
}

# stop_id: (name, latitude, longitude)
STOPS = {
    "STP-01": ("Main Gate (Demo)", 4.379, 100.965),
    "STP-02": ("Academic Block A (Demo)", 4.3825, 100.969),
    "STP-03": ("Library (Demo)", 4.385, 100.9715),
    "STP-04": ("Student Centre (Demo)", 4.387, 100.974),
    "STP-05": ("Residential Village 1 (Demo)", 4.39, 100.977),
    "STP-06": ("Residential Village 2 (Demo)", 4.388, 100.98),
    "STP-07": ("Sports Complex (Demo)", 4.383, 100.976),
}

# route_id: (name, description, colour_hex, is_loop, total_length_m)
ROUTES = {
    "RTE-A": ("Residential Loop (Demo)", "Main Gate to residential villages and back", "#E53935", 1, 4334),
    "RTE-B": ("Academic Shuttle (Demo)", "Main Gate, academic area, library and sports complex", "#1E88E5", 1, 2951),
}

# (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m)
ROUTE_STOPS = [
    ("RTE-A", 1, "STP-01", 0, 616),
    ("RTE-A", 2, "STP-02", 616, 410),
    ("RTE-A", 3, "STP-03", 1026, 371),
    ("RTE-A", 4, "STP-04", 1397, 492),
    ("RTE-A", 5, "STP-05", 1889, 418),
    ("RTE-A", 6, "STP-06", 2307, 2027),
    ("RTE-B", 1, "STP-01", 0, 616),
    ("RTE-B", 2, "STP-02", 616, 410),
    ("RTE-B", 3, "STP-03", 1026, 570),
    ("RTE-B", 4, "STP-07", 1596, 1355),
]

# (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m)
ROUTE_POINTS = [
    ("RTE-A", 1, 4.379, 100.965, "STP-01", 0),
    ("RTE-A", 2, 4.38015, 100.967525, None, 308),
    ("RTE-A", 3, 4.3825, 100.969, "STP-02", 616),
    ("RTE-A", 4, 4.383375, 100.970625, None, 821),
    ("RTE-A", 5, 4.385, 100.9715, "STP-03", 1026),
    ("RTE-A", 6, 4.385625, 100.97305, None, 1211),
    ("RTE-A", 7, 4.387, 100.974, "STP-04", 1397),
    ("RTE-A", 8, 4.38805, 100.97595, None, 1643),
    ("RTE-A", 9, 4.39, 100.977, "STP-05", 1889),
    ("RTE-A", 10, 4.38855, 100.9782, None, 2098),
    ("RTE-A", 11, 4.388, 100.98, "STP-06", 2307),
    ("RTE-A", 12, 4.38575, 100.97115, None, 3320),
    ("RTE-B", 1, 4.379, 100.965, "STP-01", 0),
    ("RTE-B", 2, 4.38015, 100.967525, None, 308),
    ("RTE-B", 3, 4.3825, 100.969, "STP-02", 616),
    ("RTE-B", 4, 4.383375, 100.970625, None, 821),
    ("RTE-B", 5, 4.385, 100.9715, "STP-03", 1026),
    ("RTE-B", 6, 4.383325, 100.97345, None, 1311),
    ("RTE-B", 7, 4.383, 100.976, "STP-07", 1596),
    ("RTE-B", 8, 4.38265, 100.9699, None, 2273),
]

# bus_id: (label, route_id, service_state)
BUSES = {
    "BUS-01": ("Demo Bus 1", "RTE-A", "IN_SERVICE"),
    "BUS-02": ("Demo Bus 2", "RTE-B", "IN_SERVICE"),
    "BUS-03": ("Demo Bus 3", None, "OUT_OF_SERVICE"),
    "BUS-04": ("Demo Bus 4", "RTE-A", "IN_SERVICE"),
}

# bus_id: (latitude, longitude, age_seconds, speed_kmh, accuracy_m, data_source)
DEMO_LOCATION_TEMPLATE = {
    "BUS-01": (4.3825, 100.969, 5, 18.0, 6.0, "SIMULATED"),
    "BUS-02": (4.385, 100.9715, 600, 0.0, 8.0, "SIMULATED"),
    "BUS-04": (4.387, 100.974, 60, 15.0, 9.0, "SIMULATED"),
}
