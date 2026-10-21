-- =====================================================================
-- Smart Campus Bus Tracker | CodeFest'26 | Database schema (Oracle, v1.2)
-- Owner: Roy (Person 3) - Database & Data Management
--
-- IMPLEMENTATION TARGET
--   Oracle Database Express Edition (XE) 21c (also works on 18c / 23ai Free).
--   Run as BUS_OWNER (see 00_create_users.sql). Needs: identity columns
--   (12c+), REGEXP_LIKE, TIMESTAMP, PL/SQL packages.
--
-- CONVENTIONS (shared contract - unchanged from v1.1, see data dictionary)
--   IDs         : upper-case prefix + digits  BUS-01  STP-01  RTE-A
--   Timestamps  : stored as TIMESTAMP(0) in UTC. The API/JSON shows them as
--                 ISO 8601 strings with a trailing Z: 2026-10-04T08:30:00Z
--                 (use pkg_bus_tracker.to_iso_utc / the *_iso view columns)
--   Coordinates : WGS84 decimal degrees (latitude, longitude)
--   Distances   : metres      Speed: km/h      ETA: minutes
--   Booleans    : NUMBER(1) 0 / 1   (works on every Oracle version)
--   Unknown     : NULL (never 0 / '' / 'N/A').  NOTE: in Oracle an empty
--                 string '' IS NULL, so blank text is also "unknown".
--   data_origin : DEMO | SURVEYED | OFFICIAL  (never show DEMO as real)
--
-- ORACLE-SPECIFIC NOTES
--   * A CHECK constraint passes when its condition is UNKNOWN (NULL).
--     So text rules are written as  TRIM(x) IS NOT NULL  (not LENGTH>0).
--   * Column "sequence" of v1.1 is called stop_sequence here (SEQUENCE is
--     an Oracle keyword). The JSON/API name stays "sequence".
--   * ID rules also reject control characters (e.g. a trailing newline) so
--     the result does not depend on how Oracle treats $ at a line end.
--   * Constraints are NAMED so an ORA-02290 message tells you which rule
--     was broken.
-- =====================================================================
SET DEFINE OFF
SET SQLBLANKLINES ON

-- ---------------------------------------------------------------------
-- Configuration (thresholds shared by every module)
-- ---------------------------------------------------------------------
CREATE TABLE system_config (
  config_key   VARCHAR2(40)  NOT NULL,
  config_value NUMBER        NOT NULL,
  unit         VARCHAR2(20)  NOT NULL,
  description  VARCHAR2(200) NOT NULL,
  CONSTRAINT pk_system_config PRIMARY KEY (config_key)
);

-- ---------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------
CREATE TABLE routes (
  route_id        VARCHAR2(20)  NOT NULL,
  name            VARCHAR2(100) NOT NULL,
  description     VARCHAR2(300),
  colour_hex      VARCHAR2(7)   DEFAULT '#1E88E5' NOT NULL,
  is_loop         NUMBER(1)     DEFAULT 1 NOT NULL,
  total_length_m  NUMBER(9)     NOT NULL,
  active          NUMBER(1)     DEFAULT 1 NOT NULL,
  data_origin     VARCHAR2(10)  NOT NULL,
  CONSTRAINT pk_routes        PRIMARY KEY (route_id),
  CONSTRAINT ck_routes_id     CHECK (REGEXP_LIKE(route_id, '^RTE-[A-Z0-9]+$', 'c') AND NOT REGEXP_LIKE(route_id, '[[:cntrl:]]')),
  CONSTRAINT ck_routes_name   CHECK (TRIM(name) IS NOT NULL),
  CONSTRAINT ck_routes_colour CHECK (REGEXP_LIKE(colour_hex, '^#[0-9A-Fa-f]{6}$', 'c') AND NOT REGEXP_LIKE(colour_hex, '[[:cntrl:]]')),
  CONSTRAINT ck_routes_loop   CHECK (is_loop IN (0,1)),
  CONSTRAINT ck_routes_len    CHECK (total_length_m > 0),
  CONSTRAINT ck_routes_active CHECK (active IN (0,1)),
  CONSTRAINT ck_routes_origin CHECK (data_origin IN ('DEMO','SURVEYED','OFFICIAL'))
);

CREATE TABLE stops (
  stop_id      VARCHAR2(20)  NOT NULL,
  name         VARCHAR2(100) NOT NULL,
  latitude     NUMBER(10,7)  NOT NULL,
  longitude    NUMBER(10,7)  NOT NULL,
  active       NUMBER(1)     DEFAULT 1 NOT NULL,
  data_origin  VARCHAR2(10)  NOT NULL,
  CONSTRAINT pk_stops        PRIMARY KEY (stop_id),
  CONSTRAINT ck_stops_id     CHECK (REGEXP_LIKE(stop_id, '^STP-[0-9]+$', 'c') AND NOT REGEXP_LIKE(stop_id, '[[:cntrl:]]')),
  CONSTRAINT ck_stops_name   CHECK (TRIM(name) IS NOT NULL),
  CONSTRAINT ck_stops_lat    CHECK (latitude  BETWEEN -90  AND 90),
  CONSTRAINT ck_stops_lng    CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT ck_stops_not00  CHECK (NOT (latitude = 0 AND longitude = 0)),
  CONSTRAINT ck_stops_active CHECK (active IN (0,1)),
  CONSTRAINT ck_stops_origin CHECK (data_origin IN ('DEMO','SURVEYED','OFFICIAL'))
);

-- Ordered stops of a route (many-to-many routes <-> stops)
CREATE TABLE route_stops (
  route_id              VARCHAR2(20) NOT NULL,
  stop_sequence         NUMBER(4)    NOT NULL,
  stop_id               VARCHAR2(20) NOT NULL,
  cumulative_distance_m NUMBER(9)    NOT NULL,
  distance_to_next_m    NUMBER(9),
  CONSTRAINT pk_route_stops      PRIMARY KEY (route_id, stop_sequence),
  CONSTRAINT uq_route_stops_stop UNIQUE (route_id, stop_id),
  CONSTRAINT fk_rs_route FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE CASCADE,
  CONSTRAINT fk_rs_stop  FOREIGN KEY (stop_id)  REFERENCES stops (stop_id),
  CONSTRAINT ck_rs_seq   CHECK (stop_sequence >= 1),
  CONSTRAINT ck_rs_cum   CHECK (cumulative_distance_m >= 0),
  CONSTRAINT ck_rs_next  CHECK (distance_to_next_m IS NULL OR distance_to_next_m > 0)
);

-- Route path polyline (drawing the route + route-aware distance).
-- v1.2: cumulative_distance_m = distance along the path from point 1.
CREATE TABLE route_points (
  route_id              VARCHAR2(20) NOT NULL,
  point_seq             NUMBER(5)    NOT NULL,
  latitude              NUMBER(10,7) NOT NULL,
  longitude             NUMBER(10,7) NOT NULL,
  stop_id               VARCHAR2(20),
  cumulative_distance_m NUMBER(9)    NOT NULL,
  CONSTRAINT pk_route_points PRIMARY KEY (route_id, point_seq),
  CONSTRAINT fk_rp_route FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE CASCADE,
  CONSTRAINT fk_rp_stop  FOREIGN KEY (stop_id)  REFERENCES stops (stop_id),
  CONSTRAINT ck_rp_seq   CHECK (point_seq >= 1),
  CONSTRAINT ck_rp_lat   CHECK (latitude  BETWEEN -90  AND 90),
  CONSTRAINT ck_rp_lng   CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT ck_rp_cum   CHECK (cumulative_distance_m >= 0)
);

CREATE TABLE buses (
  bus_id         VARCHAR2(20)  NOT NULL,
  label          VARCHAR2(100) NOT NULL,
  route_id       VARCHAR2(20),
  service_state  VARCHAR2(20)  DEFAULT 'IN_SERVICE' NOT NULL,
  data_origin    VARCHAR2(10)  NOT NULL,
  CONSTRAINT pk_buses PRIMARY KEY (bus_id),
  CONSTRAINT fk_buses_route FOREIGN KEY (route_id) REFERENCES routes (route_id) ON DELETE SET NULL,
  CONSTRAINT ck_buses_id     CHECK (REGEXP_LIKE(bus_id, '^BUS-[0-9]+$', 'c') AND NOT REGEXP_LIKE(bus_id, '[[:cntrl:]]')),
  CONSTRAINT ck_buses_label  CHECK (TRIM(label) IS NOT NULL),
  CONSTRAINT ck_buses_state  CHECK (service_state IN ('IN_SERVICE','OUT_OF_SERVICE')),
  CONSTRAINT ck_buses_origin CHECK (data_origin IN ('DEMO','SURVEYED','OFFICIAL'))
);

-- ---------------------------------------------------------------------
-- Live data: ONE row per bus = latest ACCEPTED location.
-- Only pkg_bus_tracker.apply_location_update writes here.
-- ---------------------------------------------------------------------
CREATE TABLE bus_locations (
  bus_id             VARCHAR2(20)  NOT NULL,
  latitude           NUMBER(10,7)  NOT NULL,
  longitude          NUMBER(10,7)  NOT NULL,
  location_timestamp TIMESTAMP(0)  NOT NULL,   -- GPS capture time, UTC (sender clock)
  received_at        TIMESTAMP(0)  NOT NULL,   -- backend store time, UTC (server clock)
  speed_kmh          NUMBER(6,2),
  accuracy_m         NUMBER(8,2),
  data_source        VARCHAR2(10)  NOT NULL,
  CONSTRAINT pk_bus_locations PRIMARY KEY (bus_id),
  CONSTRAINT fk_bl_bus   FOREIGN KEY (bus_id) REFERENCES buses (bus_id) ON DELETE CASCADE,
  CONSTRAINT ck_bl_lat   CHECK (latitude  BETWEEN -90  AND 90),
  CONSTRAINT ck_bl_lng   CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT ck_bl_not00 CHECK (NOT (latitude = 0 AND longitude = 0)),
  CONSTRAINT ck_bl_speed CHECK (speed_kmh IS NULL OR speed_kmh >= 0),
  CONSTRAINT ck_bl_acc   CHECK (accuracy_m IS NULL OR accuracy_m >= 0),
  CONSTRAINT ck_bl_src   CHECK (data_source IN ('LIVE','MANUAL','SIMULATED'))
);

-- DB-level safety net: an older or duplicate timestamp can never overwrite
-- the stored location, even if the backend forgets to check.
CREATE OR REPLACE TRIGGER trg_bus_locations_no_older
BEFORE UPDATE ON bus_locations
FOR EACH ROW
WHEN (NEW.location_timestamp <= OLD.location_timestamp)
BEGIN
  RAISE_APPLICATION_ERROR(-20001, 'OLDER_OR_DUPLICATE_TIMESTAMP');
END;
/

-- Audit / testing log of every update outcome (accepted AND rejected).
-- No foreign key on purpose: updates for unknown bus IDs are logged too.
-- location_timestamp is TEXT here: a malformed timestamp is logged as received.
CREATE TABLE location_log (
  log_id             NUMBER GENERATED ALWAYS AS IDENTITY,
  bus_id             VARCHAR2(40),
  latitude           NUMBER,
  longitude          NUMBER,
  location_timestamp VARCHAR2(40),
  received_at        TIMESTAMP(0) NOT NULL,
  data_source        VARCHAR2(30),
  outcome            VARCHAR2(20) NOT NULL,
  reason_code        VARCHAR2(40),
  CONSTRAINT pk_location_log PRIMARY KEY (log_id),
  CONSTRAINT ck_log_outcome  CHECK (outcome IN ('ACCEPT','IGNORE_DUPLICATE','IGNORE_OLDER','REJECT')),
  CONSTRAINT ck_log_reason   CHECK (
       (outcome = 'ACCEPT' AND reason_code = 'OK')
    OR (outcome <> 'ACCEPT' AND reason_code IS NOT NULL AND reason_code <> 'OK'))
);

-- Demo helper: the ages (seconds before "now") of the demo locations, so one
-- command re-times them before every demo. Not used by the app.
CREATE TABLE demo_location_template (
  bus_id       VARCHAR2(20)  NOT NULL,
  latitude     NUMBER(10,7)  NOT NULL,
  longitude    NUMBER(10,7)  NOT NULL,
  age_seconds  NUMBER(8)     NOT NULL,
  speed_kmh    NUMBER(6,2),
  accuracy_m   NUMBER(8,2),
  data_source  VARCHAR2(10)  DEFAULT 'SIMULATED' NOT NULL,
  CONSTRAINT pk_demo_loc_tpl PRIMARY KEY (bus_id),
  CONSTRAINT fk_demo_loc_bus FOREIGN KEY (bus_id) REFERENCES buses (bus_id) ON DELETE CASCADE,
  CONSTRAINT ck_demo_loc_age CHECK (age_seconds >= 0),
  CONSTRAINT ck_demo_loc_src CHECK (data_source IN ('LIVE','MANUAL','SIMULATED'))
);

-- Oracle does not index foreign keys automatically: index them.
CREATE INDEX idx_route_stops_stop  ON route_stops (stop_id);
CREATE INDEX idx_route_points_stop ON route_points (stop_id);
CREATE INDEX idx_buses_route       ON buses (route_id);
CREATE INDEX idx_log_bus_time      ON location_log (bus_id, received_at);

-- ---------------------------------------------------------------------
-- VIEWS (read-only helpers; same rules as pkg_bus_tracker / data_quality.py)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_route_stops AS
SELECT rs.route_id, r.name AS route_name, rs.stop_sequence, rs.stop_id, s.name AS stop_name,
       s.latitude, s.longitude, rs.cumulative_distance_m, rs.distance_to_next_m
FROM route_stops rs
JOIN routes r ON r.route_id = rs.route_id
JOIN stops  s ON s.stop_id  = rs.stop_id;

-- Freshness uses location_timestamp vs the current UTC time and the
-- thresholds in system_config. There is deliberately NO 'DELAYED' status:
-- no timetable exists, so the data cannot prove a bus is late.
CREATE OR REPLACE VIEW v_bus_status AS
WITH cfg AS (
  SELECT MAX(CASE WHEN config_key = 'stale_after_s'   THEN config_value END) AS stale_s,
         MAX(CASE WHEN config_key = 'offline_after_s' THEN config_value END) AS offline_s
  FROM system_config
),
base AS (
  SELECT b.bus_id, b.label, b.route_id, b.service_state, b.data_origin,
         l.latitude, l.longitude, l.location_timestamp, l.received_at,
         l.speed_kmh, l.accuracy_m, l.data_source,
         CASE WHEN l.bus_id IS NULL THEN 0 ELSE 1 END AS has_location,
         CASE WHEN l.bus_id IS NULL THEN NULL
              ELSE ROUND((CAST(SYS_EXTRACT_UTC(SYSTIMESTAMP) AS DATE)
                        - CAST(l.location_timestamp AS DATE)) * 86400)
         END AS age_seconds
  FROM buses b LEFT JOIN bus_locations l ON l.bus_id = b.bus_id
)
SELECT x.bus_id, x.label, x.route_id, x.service_state, x.data_origin,
       x.latitude, x.longitude, x.location_timestamp, x.received_at,
       TO_CHAR(x.location_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS timestamp_iso,
       TO_CHAR(x.received_at,        'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS received_at_iso,
       x.speed_kmh, x.accuracy_m, x.data_source, x.age_seconds,
       CASE WHEN x.has_location = 0           THEN 'UNAVAILABLE'
            WHEN x.age_seconds <= c.stale_s   THEN 'LIVE'
            WHEN x.age_seconds <= c.offline_s THEN 'STALE'
            ELSE 'OFFLINE'
       END AS data_freshness,
       CASE WHEN x.service_state = 'OUT_OF_SERVICE' THEN 'NOT_IN_SERVICE'
            WHEN x.has_location = 0                 THEN 'NO_DATA'
            WHEN x.age_seconds <= c.stale_s         THEN 'ACTIVE'
            WHEN x.age_seconds <= c.offline_s       THEN 'STALE'
            ELSE 'OFFLINE'
       END AS display_status
FROM base x CROSS JOIN cfg c;

-- ---------------------------------------------------------------------
-- COMMENTS (the data dictionary stays inside the database:
--           SELECT * FROM user_col_comments WHERE table_name = 'STOPS')
-- ---------------------------------------------------------------------
COMMENT ON TABLE system_config  IS 'Shared thresholds read by every module (reference/config)';
COMMENT ON TABLE routes         IS 'Route definitions (reference). One route = one direction';
COMMENT ON TABLE stops          IS 'Known bus stops (reference)';
COMMENT ON TABLE route_stops    IS 'Ordered stops of a route with distances along the path (reference)';
COMMENT ON TABLE route_points   IS 'Route path polyline with cumulative distance (reference)';
COMMENT ON TABLE buses          IS 'Stable bus reference data';
COMMENT ON TABLE bus_locations  IS 'LIVE: latest ACCEPTED location, one row per bus. Written only by pkg_bus_tracker';
COMMENT ON TABLE location_log   IS 'AUDIT: every update outcome. Trim regularly (pkg_bus_tracker.trim_location_log)';
COMMENT ON TABLE demo_location_template IS 'DEMO ONLY: ages used by refresh_demo_locations';

COMMENT ON COLUMN system_config.config_key   IS 'Threshold name, e.g. stale_after_s';
COMMENT ON COLUMN system_config.config_value IS 'Numeric value in the stated unit';
COMMENT ON COLUMN routes.route_id        IS 'RTE- + A-Z/0-9, e.g. RTE-A';
COMMENT ON COLUMN routes.colour_hex      IS 'Line colour on the map, #RRGGBB';
COMMENT ON COLUMN routes.is_loop         IS '1 = last stop connects back to the first';
COMMENT ON COLUMN routes.total_length_m  IS 'Length of one full circuit; equals SUM(route_stops.distance_to_next_m)';
COMMENT ON COLUMN routes.data_origin     IS 'DEMO / SURVEYED / OFFICIAL';
COMMENT ON COLUMN stops.stop_id          IS 'STP- + digits, e.g. STP-01';
COMMENT ON COLUMN stops.latitude         IS 'WGS84 degrees, -90..90';
COMMENT ON COLUMN stops.longitude        IS 'WGS84 degrees, -180..180';
COMMENT ON COLUMN stops.active           IS '0 = hidden from the app, record kept';
COMMENT ON COLUMN route_stops.stop_sequence         IS 'Position in the route 1,2,3... (JSON name: sequence)';
COMMENT ON COLUMN route_stops.cumulative_distance_m IS 'Distance along the route path from stop 1 to this stop';
COMMENT ON COLUMN route_stops.distance_to_next_m    IS 'Distance to the next stop; last stop of a loop -> back to stop 1';
COMMENT ON COLUMN route_points.point_seq             IS 'Order along the path';
COMMENT ON COLUMN route_points.stop_id               IS 'Set when this vertex IS a stop, else NULL';
COMMENT ON COLUMN route_points.cumulative_distance_m IS 'Distance along the path from point 1 (v1.2)';
COMMENT ON COLUMN buses.bus_id           IS 'BUS- + digits, e.g. BUS-01';
COMMENT ON COLUMN buses.route_id         IS 'Assigned route, NULL = unassigned';
COMMENT ON COLUMN buses.service_state    IS 'IN_SERVICE / OUT_OF_SERVICE, set by an operator (not derived from GPS)';
COMMENT ON COLUMN bus_locations.location_timestamp IS 'When the GPS fix was captured, UTC (JSON name: timestamp)';
COMMENT ON COLUMN bus_locations.received_at        IS 'When the backend stored it, UTC';
COMMENT ON COLUMN bus_locations.speed_kmh          IS 'Reported speed; NULL if unknown (not 0)';
COMMENT ON COLUMN bus_locations.accuracy_m         IS 'Reported GPS accuracy in metres';
COMMENT ON COLUMN bus_locations.data_source        IS 'LIVE (real GPS) / MANUAL (hand-entered) / SIMULATED';
COMMENT ON COLUMN location_log.location_timestamp  IS 'Timestamp text exactly as received (may be malformed)';
COMMENT ON COLUMN location_log.outcome             IS 'ACCEPT / IGNORE_DUPLICATE / IGNORE_OLDER / REJECT';
COMMENT ON COLUMN location_log.reason_code         IS 'OK for ACCEPT, otherwise a code from the data quality rules';

PROMPT 01_schema.sql done.
