-- =====================================================================
-- Smart Campus Bus Tracker | Oracle edition v1.2
-- 02_package.sql  -  business rules inside the database (run as BUS_OWNER)
--
-- This package is the Oracle equivalent of data_quality.py + apply_update.py.
-- The backend (Hazeem) calls ONE procedure for every incoming GPS update:
--
--   pkg_bus_tracker.apply_location_update(...)  -> outcome + reason_code
--
-- Rules implemented here (order = first failure decides the outcome):
--   2 MISSING_FIELD        4 UNKNOWN_BUS       5 OUT_OF_RANGE
--   6 OUTSIDE_SERVICE_AREA 7 BAD_TIMESTAMP     8 FUTURE_TIMESTAMP
--   9 DUPLICATE_TIMESTAMP (IGNORE_DUPLICATE)  10 OLDER_THAN_STORED (IGNORE_OLDER)
--  11 IMPLAUSIBLE_JUMP
--   + 3a BAD_OPTIONAL_FIELD (new in v1.2: bad dataSource, negative speed/accuracy)
-- Rules 1 (MALFORMED_PAYLOAD) and 3 (BAD_TYPE) are about JSON types; the
-- backend checks them before calling the database and records them with
-- pkg_bus_tracker.log_reject.  (Oracle bind variables are already typed.)
-- =====================================================================
SET DEFINE OFF
SET SQLBLANKLINES ON

CREATE OR REPLACE PACKAGE pkg_bus_tracker AS

  c_earth_radius_m CONSTANT NUMBER := 6371000;

  -- configuration -------------------------------------------------------
  FUNCTION cfg (p_key IN VARCHAR2) RETURN NUMBER;

  -- time helpers --------------------------------------------------------
  -- strict 'YYYY-MM-DDTHH:MM:SSZ' -> TIMESTAMP (UTC); NULL if not valid
  FUNCTION parse_iso_utc (p_text IN VARCHAR2) RETURN TIMESTAMP;
  FUNCTION to_iso_utc    (p_ts   IN TIMESTAMP) RETURN VARCHAR2;

  -- geometry ------------------------------------------------------------
  FUNCTION haversine_m (p_lat1 IN NUMBER, p_lng1 IN NUMBER,
                        p_lat2 IN NUMBER, p_lng2 IN NUMBER) RETURN NUMBER;

  -- freshness / status (same rules as view v_bus_status) ------------------
  FUNCTION freshness      (p_age_seconds IN NUMBER) RETURN VARCHAR2;
  FUNCTION display_status (p_service_state IN VARCHAR2, p_freshness IN VARCHAR2) RETURN VARCHAR2;

  -- ETA helper (reference; Wafiy owns the final ETA logic) -----------------
  -- minutes = distance / speed. NULL for missing/negative distance or
  -- missing/zero/negative speed. The CALLER substitutes default_avg_speed_kmh.
  FUNCTION eta_minutes (p_distance_m IN NUMBER, p_speed_kmh IN NUMBER) RETURN NUMBER;

  -- route-aware distance (metres) still to travel from the bus position to a
  -- stop, along the route path. NULL when it cannot be known.
  FUNCTION remaining_distance_m (p_route_id  IN VARCHAR2,
                                 p_latitude  IN NUMBER,
                                 p_longitude IN NUMBER,
                                 p_stop_id   IN VARCHAR2) RETURN NUMBER;

  -- THE entry point for every GPS update --------------------------------
  -- Use named notation. p_now is only for testing (fixed clock).
  PROCEDURE apply_location_update (
    p_bus_id      IN  VARCHAR2,
    p_latitude    IN  NUMBER,
    p_longitude   IN  NUMBER,
    p_timestamp   IN  VARCHAR2,
    p_outcome     OUT VARCHAR2,
    p_reason      OUT VARCHAR2,
    p_speed_kmh   IN  NUMBER    DEFAULT NULL,
    p_accuracy_m  IN  NUMBER    DEFAULT NULL,
    p_data_source IN  VARCHAR2  DEFAULT NULL,
    p_now         IN  TIMESTAMP DEFAULT NULL);

  -- for rules the backend detects itself (MALFORMED_PAYLOAD, BAD_TYPE)
  PROCEDURE log_reject (p_reason IN VARCHAR2,
                        p_bus_id IN VARCHAR2  DEFAULT NULL,
                        p_now    IN TIMESTAMP DEFAULT NULL);

  -- maintenance ---------------------------------------------------------
  PROCEDURE refresh_demo_locations;                       -- run before every demo
  PROCEDURE trim_location_log (p_keep_hours IN NUMBER DEFAULT 24);

END pkg_bus_tracker;
/

CREATE OR REPLACE PACKAGE BODY pkg_bus_tracker AS

  c_pi CONSTANT NUMBER := ACOS(-1);

  -- -------------------------------------------------------------------
  FUNCTION cfg (p_key IN VARCHAR2) RETURN NUMBER IS
    v_val NUMBER;
  BEGIN
    SELECT config_value INTO v_val FROM system_config WHERE config_key = p_key;
    RETURN v_val;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20010, 'MISSING_CONFIG: ' || p_key);
  END cfg;

  -- -------------------------------------------------------------------
  FUNCTION parse_iso_utc (p_text IN VARCHAR2) RETURN TIMESTAMP IS
  BEGIN
    IF p_text IS NULL OR LENGTH(p_text) <> 20     -- exactly 20 characters; also rejects a trailing newline
       OR NOT REGEXP_LIKE(p_text, '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$', 'c') THEN
      RETURN NULL;
    END IF;
    RETURN TO_TIMESTAMP(SUBSTR(p_text, 1, 19), 'YYYY-MM-DD"T"HH24:MI:SS');
  EXCEPTION
    WHEN OTHERS THEN     -- impossible date such as 2026-02-30 or hour 24
      RETURN NULL;
  END parse_iso_utc;

  FUNCTION to_iso_utc (p_ts IN TIMESTAMP) RETURN VARCHAR2 IS
  BEGIN
    RETURN TO_CHAR(p_ts, 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  END to_iso_utc;

  -- -------------------------------------------------------------------
  FUNCTION haversine_m (p_lat1 IN NUMBER, p_lng1 IN NUMBER,
                        p_lat2 IN NUMBER, p_lng2 IN NUMBER) RETURN NUMBER IS
    v_rad  NUMBER := c_pi / 180;
    v_dlat NUMBER;
    v_dlng NUMBER;
    v_a    NUMBER;
  BEGIN
    IF p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN
      RETURN NULL;
    END IF;
    v_dlat := (p_lat2 - p_lat1) * v_rad;
    v_dlng := (p_lng2 - p_lng1) * v_rad;
    v_a := POWER(SIN(v_dlat / 2), 2)
         + COS(p_lat1 * v_rad) * COS(p_lat2 * v_rad) * POWER(SIN(v_dlng / 2), 2);
    RETURN 2 * c_earth_radius_m * ASIN(SQRT(LEAST(1, v_a)));
  END haversine_m;

  -- -------------------------------------------------------------------
  FUNCTION freshness (p_age_seconds IN NUMBER) RETURN VARCHAR2 IS
  BEGIN
    IF p_age_seconds IS NULL THEN
      RETURN 'UNAVAILABLE';
    ELSIF p_age_seconds <= cfg('stale_after_s') THEN
      RETURN 'LIVE';
    ELSIF p_age_seconds <= cfg('offline_after_s') THEN
      RETURN 'STALE';
    ELSE
      RETURN 'OFFLINE';
    END IF;
  END freshness;

  FUNCTION display_status (p_service_state IN VARCHAR2, p_freshness IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_service_state = 'OUT_OF_SERVICE' THEN
      RETURN 'NOT_IN_SERVICE';
    ELSIF p_freshness = 'LIVE' THEN
      RETURN 'ACTIVE';
    ELSIF p_freshness = 'STALE' THEN
      RETURN 'STALE';
    ELSIF p_freshness = 'OFFLINE' THEN
      RETURN 'OFFLINE';
    ELSE
      RETURN 'NO_DATA';
    END IF;
  END display_status;

  -- -------------------------------------------------------------------
  FUNCTION eta_minutes (p_distance_m IN NUMBER, p_speed_kmh IN NUMBER) RETURN NUMBER IS
  BEGIN
    IF p_distance_m IS NULL OR p_distance_m < 0
       OR p_speed_kmh IS NULL OR p_speed_kmh <= 0 THEN
      RETURN NULL;
    END IF;
    RETURN ROUND(p_distance_m / (p_speed_kmh * 1000 / 60), 1);
  END eta_minutes;

  -- -------------------------------------------------------------------
  -- Projects the bus position onto the route polyline (nearest segment),
  -- converts that to a distance-along-route, and subtracts it from the
  -- stop's cumulative distance. Loops wrap around; non-loop routes return
  -- NULL if the bus is already past the stop.
  -- Local flat-earth projection per segment: accurate to well under 1 m
  -- over campus-sized distances.
  -- -------------------------------------------------------------------
  FUNCTION remaining_distance_m (p_route_id  IN VARCHAR2,
                                 p_latitude  IN NUMBER,
                                 p_longitude IN NUMBER,
                                 p_stop_id   IN VARCHAR2) RETURN NUMBER IS
    v_is_loop   routes.is_loop%TYPE;
    v_total     routes.total_length_m%TYPE;
    v_stop_cum  route_stops.cumulative_distance_m%TYPE;
    v_first_lat route_points.latitude%TYPE;
    v_first_lng route_points.longitude%TYPE;
    v_k         NUMBER := c_earth_radius_m * c_pi / 180;   -- metres per degree
    v_lat2 NUMBER; v_lng2 NUMBER; v_c2 NUMBER;
    v_cosl NUMBER; v_sx NUMBER; v_sy NUMBER; v_px NUMBER; v_py NUMBER;
    v_len2 NUMBER; v_t NUMBER; v_d NUMBER;
    v_best_d NUMBER; v_bus_cum NUMBER; v_remaining NUMBER;
  BEGIN
    IF p_route_id IS NULL OR p_latitude IS NULL OR p_longitude IS NULL OR p_stop_id IS NULL THEN
      RETURN NULL;
    END IF;

    BEGIN
      SELECT r.is_loop, r.total_length_m INTO v_is_loop, v_total
        FROM routes r WHERE r.route_id = p_route_id;
      SELECT rs.cumulative_distance_m INTO v_stop_cum
        FROM route_stops rs WHERE rs.route_id = p_route_id AND rs.stop_id = p_stop_id;
      SELECT p.latitude, p.longitude INTO v_first_lat, v_first_lng
        FROM route_points p
       WHERE p.route_id = p_route_id
         AND p.point_seq = (SELECT MIN(point_seq) FROM route_points WHERE route_id = p_route_id);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN RETURN NULL;     -- unknown route / stop not on route / no path
    END;

    FOR s IN (SELECT point_seq,
                     latitude  AS lat1, longitude AS lng1, cumulative_distance_m AS c1,
                     LEAD(latitude)              OVER (ORDER BY point_seq) AS nlat,
                     LEAD(longitude)             OVER (ORDER BY point_seq) AS nlng,
                     LEAD(cumulative_distance_m) OVER (ORDER BY point_seq) AS nc
                FROM route_points
               WHERE route_id = p_route_id
               ORDER BY point_seq)
    LOOP
      v_lat2 := s.nlat; v_lng2 := s.nlng; v_c2 := s.nc;
      IF v_lat2 IS NULL THEN                       -- last point
        IF v_is_loop = 1 THEN                      -- closing segment back to point 1
          v_lat2 := v_first_lat; v_lng2 := v_first_lng; v_c2 := v_total;
        ELSE
          CONTINUE;
        END IF;
      END IF;

      v_cosl := COS(s.lat1 * c_pi / 180);
      v_sx := (v_lng2 - s.lng1) * v_k * v_cosl;   v_sy := (v_lat2 - s.lat1) * v_k;
      v_px := (p_longitude - s.lng1) * v_k * v_cosl; v_py := (p_latitude - s.lat1) * v_k;
      v_len2 := v_sx * v_sx + v_sy * v_sy;
      IF v_len2 = 0 THEN
        v_t := 0;
      ELSE
        v_t := GREATEST(0, LEAST(1, (v_px * v_sx + v_py * v_sy) / v_len2));
      END IF;
      v_d := SQRT(POWER(v_px - v_t * v_sx, 2) + POWER(v_py - v_t * v_sy, 2));

      IF v_best_d IS NULL OR v_d < v_best_d THEN
        v_best_d  := v_d;
        v_bus_cum := s.c1 + v_t * (v_c2 - s.c1);
      END IF;
    END LOOP;

    IF v_best_d IS NULL THEN
      RETURN NULL;
    END IF;

    v_remaining := v_stop_cum - v_bus_cum;
    IF v_remaining < 0 THEN
      IF -v_remaining <= cfg('arrival_radius_m') THEN
        RETURN 0;                                  -- just passed / standing at the stop
      ELSIF v_is_loop = 1 THEN
        v_remaining := v_remaining + v_total;      -- wrap around the loop
      ELSE
        RETURN NULL;                               -- non-loop bus already past the stop
      END IF;
    END IF;
    RETURN ROUND(v_remaining);
  END remaining_distance_m;

  -- -------------------------------------------------------------------
  PROCEDURE apply_location_update (
    p_bus_id      IN  VARCHAR2,
    p_latitude    IN  NUMBER,
    p_longitude   IN  NUMBER,
    p_timestamp   IN  VARCHAR2,
    p_outcome     OUT VARCHAR2,
    p_reason      OUT VARCHAR2,
    p_speed_kmh   IN  NUMBER    DEFAULT NULL,
    p_accuracy_m  IN  NUMBER    DEFAULT NULL,
    p_data_source IN  VARCHAR2  DEFAULT NULL,
    p_now         IN  TIMESTAMP DEFAULT NULL)
  IS
    v_now      TIMESTAMP := NVL(p_now, SYS_EXTRACT_UTC(SYSTIMESTAMP));
    v_ts       TIMESTAMP;
    v_src      VARCHAR2(10);
    v_n        NUMBER;
    v_have_old BOOLEAN := FALSE;
    v_old_ts   TIMESTAMP;
    v_old_lat  NUMBER;
    v_old_lng  NUMBER;
    v_dist     NUMBER;
    v_dt       NUMBER;

    -- write the audit row, set the OUT values, commit (releases the row lock)
    PROCEDURE done (p_o IN VARCHAR2, p_r IN VARCHAR2) IS
    BEGIN
      p_outcome := p_o;
      p_reason  := p_r;
      INSERT INTO location_log (bus_id, latitude, longitude, location_timestamp,
                                received_at, data_source, outcome, reason_code)
      VALUES (SUBSTR(p_bus_id, 1, 40), p_latitude, p_longitude, SUBSTR(p_timestamp, 1, 40),
              v_now, SUBSTR(p_data_source, 1, 30), p_o, p_r);
      COMMIT;
    END done;
  BEGIN
    -- 2. required fields
    IF p_bus_id IS NULL OR p_latitude IS NULL OR p_longitude IS NULL OR p_timestamp IS NULL THEN
      done('REJECT', 'MISSING_FIELD'); RETURN;
    END IF;

    -- 3a. optional fields
    v_src := NVL(p_data_source, 'SIMULATED');   -- default until real GPS is approved
    IF v_src NOT IN ('LIVE', 'MANUAL', 'SIMULATED')
       OR p_speed_kmh < 0 OR p_accuracy_m < 0 THEN
      done('REJECT', 'BAD_OPTIONAL_FIELD'); RETURN;
    END IF;

    -- 4. known bus
    SELECT COUNT(*) INTO v_n FROM buses WHERE bus_id = p_bus_id;
    IF v_n = 0 THEN
      done('REJECT', 'UNKNOWN_BUS'); RETURN;
    END IF;

    -- 5. coordinate range
    IF p_latitude NOT BETWEEN -90 AND 90 OR p_longitude NOT BETWEEN -180 AND 180 THEN
      done('REJECT', 'OUT_OF_RANGE'); RETURN;
    END IF;

    -- 6. service area (also catches 0,0)
    IF p_latitude  NOT BETWEEN cfg('bbox_min_lat') AND cfg('bbox_max_lat')
       OR p_longitude NOT BETWEEN cfg('bbox_min_lng') AND cfg('bbox_max_lng') THEN
      done('REJECT', 'OUTSIDE_SERVICE_AREA'); RETURN;
    END IF;

    -- 7. timestamp format (strict ISO 8601 UTC, real date)
    v_ts := parse_iso_utc(p_timestamp);
    IF v_ts IS NULL THEN
      done('REJECT', 'BAD_TIMESTAMP'); RETURN;
    END IF;

    -- 8. not too far in the future
    IF (CAST(v_ts AS DATE) - CAST(v_now AS DATE)) * 86400 > cfg('max_future_skew_s') THEN
      done('REJECT', 'FUTURE_TIMESTAMP'); RETURN;
    END IF;

    -- lock this bus's stored row (if any) so two updates cannot interleave
    BEGIN
      SELECT location_timestamp, latitude, longitude
        INTO v_old_ts, v_old_lat, v_old_lng
        FROM bus_locations
       WHERE bus_id = p_bus_id
         FOR UPDATE;
      v_have_old := TRUE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN v_have_old := FALSE;   -- first update for this bus
    END;

    IF v_have_old THEN
      -- 9. duplicate / 10. older
      IF v_ts = v_old_ts THEN
        done('IGNORE_DUPLICATE', 'DUPLICATE_TIMESTAMP'); RETURN;
      ELSIF v_ts < v_old_ts THEN
        done('IGNORE_OLDER', 'OLDER_THAN_STORED'); RETURN;
      END IF;

      -- 11. implausible jump (movement under 50 m is GPS noise, never rejected)
      v_dist := haversine_m(v_old_lat, v_old_lng, p_latitude, p_longitude);
      v_dt   := (CAST(v_ts AS DATE) - CAST(v_old_ts AS DATE)) * 86400;
      IF v_dist >= 50 AND v_dt > 0
         AND (v_dist / v_dt) * 3.6 > cfg('max_jump_speed_kmh') THEN
        done('REJECT', 'IMPLAUSIBLE_JUMP'); RETURN;
      END IF;
    END IF;

    -- ACCEPT: insert the first location, or overwrite with a strictly newer one.
    MERGE INTO bus_locations t
    USING (SELECT p_bus_id AS bus_id FROM dual) s
       ON (t.bus_id = s.bus_id)
     WHEN MATCHED THEN UPDATE SET
            t.latitude = p_latitude, t.longitude = p_longitude,
            t.location_timestamp = v_ts, t.received_at = v_now,
            t.speed_kmh = p_speed_kmh, t.accuracy_m = p_accuracy_m,
            t.data_source = v_src
          WHERE t.location_timestamp < v_ts
     WHEN NOT MATCHED THEN INSERT
            (bus_id, latitude, longitude, location_timestamp, received_at,
             speed_kmh, accuracy_m, data_source)
          VALUES
            (p_bus_id, p_latitude, p_longitude, v_ts, v_now,
             p_speed_kmh, p_accuracy_m, v_src);

    done('ACCEPT', 'OK');
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END apply_location_update;

  -- -------------------------------------------------------------------
  PROCEDURE log_reject (p_reason IN VARCHAR2,
                        p_bus_id IN VARCHAR2  DEFAULT NULL,
                        p_now    IN TIMESTAMP DEFAULT NULL) IS
  BEGIN
    IF p_reason IS NULL OR p_reason NOT IN ('MALFORMED_PAYLOAD', 'BAD_TYPE') THEN
      RAISE_APPLICATION_ERROR(-20020, 'log_reject only accepts MALFORMED_PAYLOAD or BAD_TYPE');
    END IF;
    INSERT INTO location_log (bus_id, received_at, outcome, reason_code)
    VALUES (SUBSTR(p_bus_id, 1, 40), NVL(p_now, SYS_EXTRACT_UTC(SYSTIMESTAMP)), 'REJECT', p_reason);
    COMMIT;
  END log_reject;

  -- -------------------------------------------------------------------
  PROCEDURE refresh_demo_locations IS
    v_now TIMESTAMP := SYS_EXTRACT_UTC(SYSTIMESTAMP);
  BEGIN
    DELETE FROM location_log;
    DELETE FROM bus_locations;
    INSERT INTO bus_locations (bus_id, latitude, longitude, location_timestamp, received_at,
                               speed_kmh, accuracy_m, data_source)
    SELECT t.bus_id, t.latitude, t.longitude,
           v_now - NUMTODSINTERVAL(t.age_seconds, 'SECOND'),
           v_now, t.speed_kmh, t.accuracy_m, t.data_source
      FROM demo_location_template t;
    COMMIT;
  END refresh_demo_locations;

  PROCEDURE trim_location_log (p_keep_hours IN NUMBER DEFAULT 24) IS
  BEGIN
    DELETE FROM location_log
     WHERE received_at < SYS_EXTRACT_UTC(SYSTIMESTAMP) - NUMTODSINTERVAL(p_keep_hours, 'HOUR');
    COMMIT;
  END trim_location_log;

END pkg_bus_tracker;
/

SHOW ERRORS PACKAGE pkg_bus_tracker
SHOW ERRORS PACKAGE BODY pkg_bus_tracker
PROMPT 02_package.sql done.
