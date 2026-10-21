-- =====================================================================
-- Smart Campus Bus Tracker | Oracle edition | 03_seed.sql  (GENERATED)
-- Source: seed/seed.json v1.2  -  do not edit by hand;
-- change seed/build_seed.py and run seed/make_oracle_seed.py instead.
-- DEMO/SIMULATED DATA. Coordinates approximate, not surveyed. Not a real live service.
-- =====================================================================
SET DEFINE OFF

-- system_config (11 rows)
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('update_interval_s', 5, 'seconds', 'Expected interval between GPS updates from the sender');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('stale_after_s', 30, 'seconds', 'Age above which a location is STALE (not shown as live)');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('offline_after_s', 120, 'seconds', 'Age above which the bus is treated as OFFLINE');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('max_future_skew_s', 60, 'seconds', 'Max allowed timestamp ahead of server clock');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('max_jump_speed_kmh', 100, 'km/h', 'Implied speed between consecutive updates above which an update is rejected');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('default_avg_speed_kmh', 20, 'km/h', 'Fallback average bus speed for ETA (Wafiy may tune)');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('arrival_radius_m', 30, 'metres', 'A bus within this distance of a stop counts as arrived (ETA = 0, alert geofence)');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('bbox_min_lat', 4.34, 'degrees', 'Service-area bounding box (demo value, verify)');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('bbox_max_lat', 4.43, 'degrees', 'Service-area bounding box (demo value, verify)');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('bbox_min_lng', 100.92, 'degrees', 'Service-area bounding box (demo value, verify)');
INSERT INTO system_config (config_key, config_value, unit, description) VALUES ('bbox_max_lng', 101.02, 'degrees', 'Service-area bounding box (demo value, verify)');

-- stops (7 rows)
INSERT INTO stops (stop_id, name, latitude, longitude, active, data_origin) VALUES ('STP-01', 'Main Gate (Demo)', 4.379, 100.965, 1, 'DEMO');
INSERT INTO stops (stop_id, name, latitude, longitude, active, data_origin) VALUES ('STP-02', 'Academic Block A (Demo)', 4.3825, 100.969, 1, 'DEMO');
INSERT INTO stops (stop_id, name, latitude, longitude, active, data_origin) VALUES ('STP-03', 'Library (Demo)', 4.385, 100.9715, 1, 'DEMO');
INSERT INTO stops (stop_id, name, latitude, longitude, active, data_origin) VALUES ('STP-04', 'Student Centre (Demo)', 4.387, 100.974, 1, 'DEMO');
INSERT INTO stops (stop_id, name, latitude, longitude, active, data_origin) VALUES ('STP-05', 'Residential Village 1 (Demo)', 4.39, 100.977, 1, 'DEMO');
INSERT INTO stops (stop_id, name, latitude, longitude, active, data_origin) VALUES ('STP-06', 'Residential Village 2 (Demo)', 4.388, 100.98, 1, 'DEMO');
INSERT INTO stops (stop_id, name, latitude, longitude, active, data_origin) VALUES ('STP-07', 'Sports Complex (Demo)', 4.383, 100.976, 1, 'DEMO');

-- routes (2 rows)
INSERT INTO routes (route_id, name, description, colour_hex, is_loop, total_length_m, active, data_origin) VALUES ('RTE-A', 'Residential Loop (Demo)', 'Main Gate to residential villages and back', '#E53935', 1, 4334, 1, 'DEMO');
INSERT INTO routes (route_id, name, description, colour_hex, is_loop, total_length_m, active, data_origin) VALUES ('RTE-B', 'Academic Shuttle (Demo)', 'Main Gate, academic area, library and sports complex', '#1E88E5', 1, 2951, 1, 'DEMO');

-- route_stops (10 rows)
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-A', 1, 'STP-01', 0, 616);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-A', 2, 'STP-02', 616, 410);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-A', 3, 'STP-03', 1026, 371);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-A', 4, 'STP-04', 1397, 492);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-A', 5, 'STP-05', 1889, 418);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-A', 6, 'STP-06', 2307, 2027);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-B', 1, 'STP-01', 0, 616);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-B', 2, 'STP-02', 616, 410);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-B', 3, 'STP-03', 1026, 570);
INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-B', 4, 'STP-07', 1596, 1355);

-- route_points (20 rows)
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 1, 4.379, 100.965, 'STP-01', 0);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 2, 4.38015, 100.967525, NULL, 308);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 3, 4.3825, 100.969, 'STP-02', 616);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 4, 4.383375, 100.970625, NULL, 821);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 5, 4.385, 100.9715, 'STP-03', 1026);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 6, 4.385625, 100.97305, NULL, 1211);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 7, 4.387, 100.974, 'STP-04', 1397);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 8, 4.38805, 100.97595, NULL, 1643);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 9, 4.39, 100.977, 'STP-05', 1889);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 10, 4.38855, 100.9782, NULL, 2098);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 11, 4.388, 100.98, 'STP-06', 2307);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-A', 12, 4.38575, 100.97115, NULL, 3320);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-B', 1, 4.379, 100.965, 'STP-01', 0);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-B', 2, 4.38015, 100.967525, NULL, 308);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-B', 3, 4.3825, 100.969, 'STP-02', 616);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-B', 4, 4.383375, 100.970625, NULL, 821);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-B', 5, 4.385, 100.9715, 'STP-03', 1026);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-B', 6, 4.383325, 100.97345, NULL, 1311);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-B', 7, 4.383, 100.976, 'STP-07', 1596);
INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-B', 8, 4.38265, 100.9699, NULL, 2273);

-- buses (4 rows)
INSERT INTO buses (bus_id, label, route_id, service_state, data_origin) VALUES ('BUS-01', 'Demo Bus 1', 'RTE-A', 'IN_SERVICE', 'DEMO');
INSERT INTO buses (bus_id, label, route_id, service_state, data_origin) VALUES ('BUS-02', 'Demo Bus 2', 'RTE-B', 'IN_SERVICE', 'DEMO');
INSERT INTO buses (bus_id, label, route_id, service_state, data_origin) VALUES ('BUS-03', 'Demo Bus 3', NULL, 'OUT_OF_SERVICE', 'DEMO');
INSERT INTO buses (bus_id, label, route_id, service_state, data_origin) VALUES ('BUS-04', 'Demo Bus 4', 'RTE-A', 'IN_SERVICE', 'DEMO');

-- demo_location_template (3 rows)
INSERT INTO demo_location_template (bus_id, latitude, longitude, age_seconds, speed_kmh, accuracy_m, data_source) VALUES ('BUS-01', 4.3825, 100.969, 5, 18.0, 6.0, 'SIMULATED');
INSERT INTO demo_location_template (bus_id, latitude, longitude, age_seconds, speed_kmh, accuracy_m, data_source) VALUES ('BUS-02', 4.385, 100.9715, 600, 0.0, 8.0, 'SIMULATED');
INSERT INTO demo_location_template (bus_id, latitude, longitude, age_seconds, speed_kmh, accuracy_m, data_source) VALUES ('BUS-04', 4.387, 100.974, 60, 15.0, 9.0, 'SIMULATED');

COMMIT;

-- Turn the demo ages (5 s / 60 s / 600 s) into real timestamps relative to NOW.
BEGIN
  pkg_bus_tracker.refresh_demo_locations;
END;
/

PROMPT 03_seed.sql done (demo data loaded, locations re-timed to now).
