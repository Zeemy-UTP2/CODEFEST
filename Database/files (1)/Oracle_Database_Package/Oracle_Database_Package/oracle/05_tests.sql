-- =====================================================================
-- 05_tests.sql  -  automated test suite for the Oracle database (v1.2)
-- Run as BUS_OWNER after install_all.sql:
--     @05_tests.sql
-- Prints PASS / FAIL per case and a summary. Re-loads the demo data at
-- the end, so it is safe to run any time. Same case IDs as
-- tests/test_data_quality.py (V = validation, F/S/E = freshness/status/ETA,
-- R = route distance) plus T = database rules.
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
PROMPT ===== Smart Campus Bus Tracker - Oracle test suite (v1.2) =====

DECLARE
  g_pass PLS_INTEGER := 0;
  g_fail PLS_INTEGER := 0;
  c_now  CONSTANT TIMESTAMP := TIMESTAMP '2026-10-04 08:30:00';   -- fixed test clock

  -- ---------- helpers ----------
  PROCEDURE ok (p_id VARCHAR2, p_desc VARCHAR2, p_cond BOOLEAN) IS
  BEGIN
    IF p_cond THEN
      g_pass := g_pass + 1;
      DBMS_OUTPUT.PUT_LINE('PASS ' || RPAD(p_id, 7) || p_desc);
    ELSE
      g_fail := g_fail + 1;
      DBMS_OUTPUT.PUT_LINE('FAIL ' || RPAD(p_id, 7) || p_desc);
    END IF;
  END ok;

  FUNCTION cnt (p_sql VARCHAR2) RETURN NUMBER IS
    v_n NUMBER;
  BEGIN
    EXECUTE IMMEDIATE p_sql INTO v_n;
    RETURN v_n;
  END cnt;

  -- stored location of a bus = 4.3825, 100.969 at 08:29:55 (5 s before c_now)
  PROCEDURE reset_bus (p_bus VARCHAR2) IS
  BEGIN
    DELETE FROM bus_locations WHERE bus_id = p_bus;
    INSERT INTO bus_locations (bus_id, latitude, longitude, location_timestamp, received_at,
                               speed_kmh, accuracy_m, data_source)
    VALUES (p_bus, 4.3825, 100.969, TIMESTAMP '2026-10-04 08:29:55',
            TIMESTAMP '2026-10-04 08:30:00', 18, 6, 'SIMULATED');
    COMMIT;
  END reset_bus;

  -- send one update (BUS-01 reset to the baseline first) and compare outcome/reason
  PROCEDURE t_upd (p_id VARCHAR2, p_desc VARCHAR2, p_exp_o VARCHAR2, p_exp_r VARCHAR2,
                   p_bus VARCHAR2, p_lat NUMBER, p_lng NUMBER, p_ts VARCHAR2,
                   p_src VARCHAR2 DEFAULT NULL, p_speed NUMBER DEFAULT NULL,
                   p_reset BOOLEAN DEFAULT TRUE) IS
    v_o VARCHAR2(30);
    v_r VARCHAR2(60);
  BEGIN
    IF p_reset THEN reset_bus('BUS-01'); END IF;
    pkg_bus_tracker.apply_location_update(
      p_bus_id => p_bus, p_latitude => p_lat, p_longitude => p_lng, p_timestamp => p_ts,
      p_outcome => v_o, p_reason => v_r,
      p_speed_kmh => p_speed, p_data_source => p_src, p_now => c_now);
    ok(p_id, p_desc || ' -> ' || v_o || '/' || v_r, v_o = p_exp_o AND v_r = p_exp_r);
  END t_upd;

  -- a statement the database MUST refuse (optionally with a specific ORA code)
  PROCEDURE must_fail (p_id VARCHAR2, p_desc VARCHAR2, p_sql VARCHAR2, p_code NUMBER DEFAULT NULL) IS
    v_failed BOOLEAN := FALSE;
    v_code   NUMBER;
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE p_sql;
    EXCEPTION
      WHEN OTHERS THEN v_failed := TRUE; v_code := SQLCODE;
    END;
    ROLLBACK;
    ok(p_id, p_desc || CASE WHEN v_failed THEN ' (blocked, ORA' || v_code || ')' ELSE ' (NOT BLOCKED!)' END,
       v_failed AND (p_code IS NULL OR v_code = p_code));
  END must_fail;

  -- a statement the database MUST accept
  PROCEDURE must_pass (p_id VARCHAR2, p_desc VARCHAR2, p_sql VARCHAR2) IS
    v_failed BOOLEAN := FALSE;
    v_msg    VARCHAR2(200);
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE p_sql;
    EXCEPTION
      WHEN OTHERS THEN v_failed := TRUE; v_msg := SUBSTR(SQLERRM, 1, 120);
    END;
    ROLLBACK;
    ok(p_id, p_desc || CASE WHEN v_failed THEN ' (REFUSED: ' || v_msg || ')' ELSE ' (accepted)' END, NOT v_failed);
  END must_pass;

  v_n   NUMBER;
  v_ts  TIMESTAMP;
  v_lat NUMBER;
  v_o   VARCHAR2(30);
  v_r   VARCHAR2(60);
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- 6.1 location update validation (package) ---');
  t_upd('V01', 'valid newer update',                'ACCEPT', 'OK', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:30:00Z');
  -- first ever update for a bus that has no stored location
  DELETE FROM bus_locations WHERE bus_id = 'BUS-04'; COMMIT;
  t_upd('V02', 'first ever update for a bus',       'ACCEPT', 'OK', 'BUS-04', 4.387, 100.974, '2026-10-04T08:30:00Z', p_reset => FALSE);
  t_upd('V03', 'missing busId',                     'REJECT', 'MISSING_FIELD', NULL, 4.3827, 100.9692, '2026-10-04T08:30:00Z');
  t_upd('V04', 'missing timestamp',                 'REJECT', 'MISSING_FIELD', 'BUS-01', 4.3827, 100.9692, NULL);
  t_upd('V05', 'null latitude',                     'REJECT', 'MISSING_FIELD', 'BUS-01', NULL, 100.9692, '2026-10-04T08:30:00Z');
  t_upd('V08', 'unknown bus BUS-99',                'REJECT', 'UNKNOWN_BUS', 'BUS-99', 4.3827, 100.9692, '2026-10-04T08:30:00Z');
  t_upd('V09', 'latitude 91',                       'REJECT', 'OUT_OF_RANGE', 'BUS-01', 91, 100.9692, '2026-10-04T08:30:00Z');
  t_upd('V10', 'longitude -181',                    'REJECT', 'OUT_OF_RANGE', 'BUS-01', 4.3827, -181, '2026-10-04T08:30:00Z');
  t_upd('V11', '(0,0)',                             'REJECT', 'OUTSIDE_SERVICE_AREA', 'BUS-01', 0, 0, '2026-10-04T08:30:00Z');
  t_upd('V12', 'valid but far away (Kuala Lumpur)', 'REJECT', 'OUTSIDE_SERVICE_AREA', 'BUS-01', 3.139, 101.6869, '2026-10-04T08:30:00Z');
  t_upd('V13', 'timestamp 04/10/2026 08:30',        'REJECT', 'BAD_TIMESTAMP', 'BUS-01', 4.3827, 100.9692, '04/10/2026 08:30');
  t_upd('V14', 'timestamp without Z',               'REJECT', 'BAD_TIMESTAMP', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:30:00');
  t_upd('V13b','impossible date 2026-02-30',        'REJECT', 'BAD_TIMESTAMP', 'BUS-01', 4.3827, 100.9692, '2026-02-30T08:30:00Z');
  t_upd('V13c','trailing newline in timestamp',     'REJECT', 'BAD_TIMESTAMP', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:30:00Z' || CHR(10));
  t_upd('V15', '10 minutes in the future',          'REJECT', 'FUTURE_TIMESTAMP', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:40:00Z');
  t_upd('V16', '30 s in the future (clock skew)',   'ACCEPT', 'OK', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:30:30Z');
  t_upd('V17', 'same timestamp as stored',          'IGNORE_DUPLICATE', 'DUPLICATE_TIMESTAMP', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:29:55Z');
  t_upd('V18', 'older than stored',                 'IGNORE_OLDER', 'OLDER_THAN_STORED', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:29:50Z');
  t_upd('V19', 'about 5 km in 10 s',                'REJECT', 'IMPLAUSIBLE_JUMP', 'BUS-01', 4.4275, 100.969, '2026-10-04T08:30:05Z');
  t_upd('V21', 'small GPS jitter under 50 m',       'ACCEPT', 'OK', 'BUS-01', 4.38253, 100.96903, '2026-10-04T08:29:56Z');
  t_upd('V22', 'bad dataSource',                    'REJECT', 'BAD_OPTIONAL_FIELD', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:30:00Z', p_src => 'GPS');
  t_upd('V23', 'negative speed',                    'REJECT', 'BAD_OPTIONAL_FIELD', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:30:00Z', p_speed => -1);
  t_upd('V24', 'dataSource omitted (defaults to SIMULATED)', 'ACCEPT', 'OK', 'BUS-01', 4.3827, 100.9692, '2026-10-04T08:30:00Z', p_speed => 18);

  -- backend-detected rules (JSON level)
  pkg_bus_tracker.log_reject('MALFORMED_PAYLOAD', p_now => c_now);
  ok('V20', 'payload is a string -> backend logs MALFORMED_PAYLOAD',
     cnt(q'[SELECT COUNT(*) FROM location_log WHERE outcome='REJECT' AND reason_code='MALFORMED_PAYLOAD']') >= 1);
  pkg_bus_tracker.log_reject('BAD_TYPE', 'BUS-01', c_now);
  ok('V06', 'latitude as string -> backend logs BAD_TYPE',
     cnt(q'[SELECT COUNT(*) FROM location_log WHERE outcome='REJECT' AND reason_code='BAD_TYPE']') >= 1);
  v_n := 0;
  BEGIN
    pkg_bus_tracker.log_reject('SOMETHING_ELSE');
  EXCEPTION WHEN OTHERS THEN v_n := SQLCODE;
  END;
  ok('V25', 'log_reject refuses other codes (ORA-20020)', v_n = -20020);

  -- rejected updates must not change the stored location
  reset_bus('BUS-01');
  pkg_bus_tracker.apply_location_update(p_bus_id => 'BUS-01', p_latitude => 91, p_longitude => 100.9,
     p_timestamp => '2026-10-04T08:30:00Z', p_outcome => v_o, p_reason => v_r, p_now => c_now);
  pkg_bus_tracker.apply_location_update(p_bus_id => 'BUS-01', p_latitude => 4.3827, p_longitude => 100.9692,
     p_timestamp => '2026-10-04T08:29:50Z', p_outcome => v_o, p_reason => v_r, p_now => c_now);
  SELECT latitude, location_timestamp INTO v_lat, v_ts FROM bus_locations WHERE bus_id = 'BUS-01';
  ok('V26', 'rejected + older updates leave the stored location untouched',
     v_lat = 4.3825 AND v_ts = TIMESTAMP '2026-10-04 08:29:55');

  DBMS_OUTPUT.PUT_LINE('--- 6.2 freshness, status, ETA, time helpers ---');
  ok('F01', 'age 5 s -> LIVE',          pkg_bus_tracker.freshness(5)     = 'LIVE');
  ok('F02', 'age 30 s -> LIVE',         pkg_bus_tracker.freshness(30)    = 'LIVE');
  ok('F03', 'age 31 s -> STALE',        pkg_bus_tracker.freshness(31)    = 'STALE');
  ok('F04', 'age 120 s -> STALE',       pkg_bus_tracker.freshness(120)   = 'STALE');
  ok('F05', 'age 121 s -> OFFLINE',     pkg_bus_tracker.freshness(121)   = 'OFFLINE');
  ok('F06', 'age 1 day -> OFFLINE',     pkg_bus_tracker.freshness(86400) = 'OFFLINE');
  ok('F07', 'no age -> UNAVAILABLE',    pkg_bus_tracker.freshness(NULL)  = 'UNAVAILABLE');
  ok('F08', 'garbage timestamp has no age -> UNAVAILABLE',
     pkg_bus_tracker.parse_iso_utc('garbage') IS NULL AND pkg_bus_tracker.freshness(NULL) = 'UNAVAILABLE');
  ok('S01', 'OUT_OF_SERVICE x LIVE',        pkg_bus_tracker.display_status('OUT_OF_SERVICE', 'LIVE') = 'NOT_IN_SERVICE');
  ok('S02', 'OUT_OF_SERVICE x UNAVAILABLE', pkg_bus_tracker.display_status('OUT_OF_SERVICE', 'UNAVAILABLE') = 'NOT_IN_SERVICE');
  ok('S03', 'IN_SERVICE x LIVE',            pkg_bus_tracker.display_status('IN_SERVICE', 'LIVE') = 'ACTIVE');
  ok('S04', 'IN_SERVICE x STALE',           pkg_bus_tracker.display_status('IN_SERVICE', 'STALE') = 'STALE');
  ok('S05', 'IN_SERVICE x OFFLINE',         pkg_bus_tracker.display_status('IN_SERVICE', 'OFFLINE') = 'OFFLINE');
  ok('S06', 'IN_SERVICE x UNAVAILABLE',     pkg_bus_tracker.display_status('IN_SERVICE', 'UNAVAILABLE') = 'NO_DATA');
  ok('E01', '1000 m at 20 km/h = 3.0 min',  pkg_bus_tracker.eta_minutes(1000, 20) = 3.0);
  ok('E02', 'zero speed -> NULL',           pkg_bus_tracker.eta_minutes(1000, 0) IS NULL);
  ok('E03', 'negative speed -> NULL',       pkg_bus_tracker.eta_minutes(1000, -5) IS NULL);
  ok('E04', 'missing speed -> NULL',        pkg_bus_tracker.eta_minutes(1000, NULL) IS NULL);
  ok('E05', 'missing distance -> NULL',     pkg_bus_tracker.eta_minutes(NULL, 20) IS NULL);
  ok('E06', 'negative distance -> NULL',    pkg_bus_tracker.eta_minutes(-1, 20) IS NULL);
  ok('E07', '0 m -> 0.0',                   pkg_bus_tracker.eta_minutes(0, 20) = 0);
  ok('P01', 'parse_iso_utc valid',          pkg_bus_tracker.parse_iso_utc('2026-10-04T08:30:00Z') = TIMESTAMP '2026-10-04 08:30:00');
  ok('P02', 'to_iso_utc round trip',        pkg_bus_tracker.to_iso_utc(TIMESTAMP '2026-10-04 08:30:00') = '2026-10-04T08:30:00Z');
  ok('P03', 'haversine 0.045 deg latitude ~ 5003.8 m',
     ABS(pkg_bus_tracker.haversine_m(4.3825, 100.969, 4.4275, 100.969) - 5003.77) < 1);

  DBMS_OUTPUT.PUT_LINE('--- 6.2 route-aware distance ---');
  ok('R01', 'loop wrap-around: bus at STP-06 -> STP-01 = 2027 m',
     pkg_bus_tracker.remaining_distance_m('RTE-A', 4.388, 100.98, 'STP-01') = 2027);
  ok('R02', 'bus before stop: bus at STP-01 -> STP-03 = 1026 m',
     pkg_bus_tracker.remaining_distance_m('RTE-A', 4.379, 100.965, 'STP-03') = 1026);
  ok('R03', 'bus at the stop itself = 0',
     pkg_bus_tracker.remaining_distance_m('RTE-A', 4.3825, 100.969, 'STP-02') = 0);
  ok('R04', 'next stop: bus at STP-02 -> STP-03 = 410 m',
     pkg_bus_tracker.remaining_distance_m('RTE-A', 4.3825, 100.969, 'STP-03') = 410);
  ok('R07', '10 m past STP-02 counts as arrived (0)',
     pkg_bus_tracker.remaining_distance_m('RTE-A', 4.38254375, 100.96908125, 'STP-02') = 0);
  ok('R08', 'stop not on this route -> NULL',
     pkg_bus_tracker.remaining_distance_m('RTE-A', 4.379, 100.965, 'STP-07') IS NULL);
  ok('R10', 'unknown route -> NULL',
     pkg_bus_tracker.remaining_distance_m('RTE-Z', 4.379, 100.965, 'STP-01') IS NULL);
  -- non-loop route (temporary rows, rolled back)
  INSERT INTO routes (route_id, name, is_loop, total_length_m, data_origin) VALUES ('RTE-T', 'Temp non-loop', 0, 616, 'DEMO');
  INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-T', 1, 'STP-01', 0, 616);
  INSERT INTO route_stops (route_id, stop_sequence, stop_id, cumulative_distance_m, distance_to_next_m) VALUES ('RTE-T', 2, 'STP-02', 616, NULL);
  INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-T', 1, 4.379, 100.965, 'STP-01', 0);
  INSERT INTO route_points (route_id, point_seq, latitude, longitude, stop_id, cumulative_distance_m) VALUES ('RTE-T', 2, 4.3825, 100.969, 'STP-02', 616);
  ok('R05', 'non-loop bus already past the stop -> NULL',
     pkg_bus_tracker.remaining_distance_m('RTE-T', 4.3825, 100.969, 'STP-01') IS NULL);
  ok('R06', 'non-loop bus before the stop = 616 m',
     pkg_bus_tracker.remaining_distance_m('RTE-T', 4.379, 100.965, 'STP-02') = 616);
  ROLLBACK;

  DBMS_OUTPUT.PUT_LINE('--- T-ID / T-RNG: format and range rules ---');
  must_fail('T-ID1', 'route id RTE-A!',          q'[INSERT INTO routes (route_id,name,total_length_m,data_origin) VALUES ('RTE-A!','x',10,'DEMO')]', -2290);
  must_fail('T-ID2', 'route id RTE- (empty suffix)', q'[INSERT INTO routes (route_id,name,total_length_m,data_origin) VALUES ('RTE-','x',10,'DEMO')]', -2290);
  must_fail('T-ID3', 'route id RTE-a (lower case)',  q'[INSERT INTO routes (route_id,name,total_length_m,data_origin) VALUES ('RTE-a','x',10,'DEMO')]', -2290);
  must_fail('T-ID4', 'route id with trailing newline', q'[INSERT INTO routes (route_id,name,total_length_m,data_origin) VALUES ('RTE-A' || CHR(10),'x',10,'DEMO')]', -2290);
  must_fail('T-ID5', 'route id wrong prefix XYZ-1',  q'[INSERT INTO routes (route_id,name,total_length_m,data_origin) VALUES ('XYZ-1','x',10,'DEMO')]', -2290);
  must_pass('T-ID6', 'route id RTE-Z9 is valid',     q'[INSERT INTO routes (route_id,name,total_length_m,data_origin) VALUES ('RTE-Z9','x',10,'DEMO')]');
  must_fail('T-ID7', 'stop id STP-01!',              q'[INSERT INTO stops (stop_id,name,latitude,longitude,data_origin) VALUES ('STP-01!','x',4.38,100.97,'DEMO')]', -2290);
  must_fail('T-ID8', 'stop id STP-A1',               q'[INSERT INTO stops (stop_id,name,latitude,longitude,data_origin) VALUES ('STP-A1','x',4.38,100.97,'DEMO')]', -2290);
  must_pass('T-ID9', 'stop id STP-99 is valid',      q'[INSERT INTO stops (stop_id,name,latitude,longitude,data_origin) VALUES ('STP-99','x',4.38,100.97,'DEMO')]');
  must_fail('T-ID10','bus id BUS-01!',               q'[INSERT INTO buses (bus_id,label,data_origin) VALUES ('BUS-01!','x','DEMO')]', -2290);
  must_fail('T-ID11','bus id BUS-X1',                q'[INSERT INTO buses (bus_id,label,data_origin) VALUES ('BUS-X1','x','DEMO')]', -2290);
  must_fail('T-ID12','bus id bus-05 (lower case)',   q'[INSERT INTO buses (bus_id,label,data_origin) VALUES ('bus-05','x','DEMO')]', -2290);
  must_pass('T-ID13','bus id BUS-05 is valid',       q'[INSERT INTO buses (bus_id,label,data_origin) VALUES ('BUS-05','x','DEMO')]');
  must_fail('T-RNG1','stop latitude 91',             q'[INSERT INTO stops (stop_id,name,latitude,longitude,data_origin) VALUES ('STP-98','x',91,100.97,'DEMO')]', -2290);
  must_fail('T-RNG2','stop longitude -181',          q'[INSERT INTO stops (stop_id,name,latitude,longitude,data_origin) VALUES ('STP-98','x',4.38,-181,'DEMO')]', -2290);
  must_fail('T-RNG3','stop at (0,0)',                q'[INSERT INTO stops (stop_id,name,latitude,longitude,data_origin) VALUES ('STP-98','x',0,0,'DEMO')]', -2290);
  must_fail('T-RNG4','blank stop name (spaces only)',q'[INSERT INTO stops (stop_id,name,latitude,longitude,data_origin) VALUES ('STP-98','   ',4.38,100.97,'DEMO')]', -2290);
  must_fail('T-RNG5','empty stop name (Oracle: NULL)', q'[INSERT INTO stops (stop_id,name,latitude,longitude,data_origin) VALUES ('STP-98','',4.38,100.97,'DEMO')]');
  must_fail('T-RNG6','service_state DELAYED not allowed', q'[INSERT INTO buses (bus_id,label,service_state,data_origin) VALUES ('BUS-05','x','DELAYED','DEMO')]', -2290);
  must_fail('T-RNG7','bad colour #12345G',           q'[INSERT INTO routes (route_id,name,colour_hex,total_length_m,data_origin) VALUES ('RTE-Z9','x','#12345G',10,'DEMO')]', -2290);
  must_fail('T-RNG8','data_origin REAL not allowed', q'[INSERT INTO routes (route_id,name,total_length_m,data_origin) VALUES ('RTE-Z9','x',10,'REAL')]', -2290);
  must_fail('T-RNG9','negative speed in bus_locations', q'[INSERT INTO bus_locations (bus_id,latitude,longitude,location_timestamp,received_at,speed_kmh,data_source) VALUES ('BUS-03',4.38,100.97,SYSTIMESTAMP,SYSTIMESTAMP,-1,'SIMULATED')]', -2290);
  must_fail('T-RNG10','data_source GPS not allowed', q'[INSERT INTO bus_locations (bus_id,latitude,longitude,location_timestamp,received_at,data_source) VALUES ('BUS-03',4.38,100.97,SYSTIMESTAMP,SYSTIMESTAMP,'GPS')]', -2290);

  DBMS_OUTPUT.PUT_LINE('--- T-FK: references and ordering ---');
  must_fail('T-FK1', 'bus with unknown route',       q'[INSERT INTO buses (bus_id,label,route_id,data_origin) VALUES ('BUS-06','x','RTE-ZZ','DEMO')]', -2291);
  must_fail('T-FK2', 'route_stop with unknown stop', q'[INSERT INTO route_stops VALUES ('RTE-A',7,'STP-99',4000,100)]', -2291);
  must_fail('T-FK3', 'same stop twice on a route',   q'[INSERT INTO route_stops VALUES ('RTE-A',7,'STP-01',4000,100)]', -1);
  must_fail('T-FK4', 'reused sequence number',       q'[INSERT INTO route_stops VALUES ('RTE-A',1,'STP-07',4000,100)]', -1);
  must_fail('T-FK5', 'delete a stop still in use',   q'[DELETE FROM stops WHERE stop_id = 'STP-01']', -2292);
  must_fail('T-FK6', 'location for unknown bus',     q'[INSERT INTO bus_locations (bus_id,latitude,longitude,location_timestamp,received_at,data_source) VALUES ('BUS-77',4.38,100.97,SYSTIMESTAMP,SYSTIMESTAMP,'SIMULATED')]', -2291);
  INSERT INTO buses (bus_id, label, data_origin) VALUES ('BUS-07', 'temp', 'DEMO');
  INSERT INTO bus_locations (bus_id, latitude, longitude, location_timestamp, received_at, data_source)
    VALUES ('BUS-07', 4.38, 100.97, TIMESTAMP '2026-10-04 08:30:00', TIMESTAMP '2026-10-04 08:30:00', 'SIMULATED');
  DELETE FROM buses WHERE bus_id = 'BUS-07';
  ok('T-FK7', 'deleting a bus also deletes its location (cascade)',
     cnt(q'[SELECT COUNT(*) FROM bus_locations WHERE bus_id = 'BUS-07']') = 0);
  ROLLBACK;

  DBMS_OUTPUT.PUT_LINE('--- T-OLD: trigger safety net ---');
  reset_bus('BUS-01');
  must_fail('T-OLD1', 'direct UPDATE to an older timestamp',
            q'[UPDATE bus_locations SET latitude = 4.3826, location_timestamp = TIMESTAMP '2026-10-04 08:29:50' WHERE bus_id = 'BUS-01']', -20001);
  must_fail('T-OLD2', 'direct UPDATE with the same timestamp',
            q'[UPDATE bus_locations SET latitude = 4.3826 WHERE bus_id = 'BUS-01']', -20001);
  must_pass('T-OLD3', 'direct UPDATE with a newer timestamp is allowed',
            q'[UPDATE bus_locations SET latitude = 4.3826, location_timestamp = TIMESTAMP '2026-10-04 08:30:10' WHERE bus_id = 'BUS-01']');

  DBMS_OUTPUT.PUT_LINE('--- T-LOG: log consistency ---');
  must_fail('T-LOG1', 'ACCEPT with a reason other than OK', q'[INSERT INTO location_log (received_at,outcome,reason_code) VALUES (SYSTIMESTAMP,'ACCEPT','BAD')]', -2290);
  must_fail('T-LOG2', 'REJECT with reason OK',              q'[INSERT INTO location_log (received_at,outcome,reason_code) VALUES (SYSTIMESTAMP,'REJECT','OK')]', -2290);
  must_fail('T-LOG3', 'REJECT without a reason',            q'[INSERT INTO location_log (received_at,outcome,reason_code) VALUES (SYSTIMESTAMP,'REJECT',NULL)]', -2290);
  must_fail('T-LOG4', 'unknown outcome value',              q'[INSERT INTO location_log (received_at,outcome,reason_code) VALUES (SYSTIMESTAMP,'MAYBE','X')]', -2290);
  must_pass('T-LOG5', 'ACCEPT with OK',                     q'[INSERT INTO location_log (received_at,outcome,reason_code) VALUES (SYSTIMESTAMP,'ACCEPT','OK')]');
  must_pass('T-LOG6', 'unknown bus id can be logged (no FK on purpose)', q'[INSERT INTO location_log (bus_id,received_at,outcome,reason_code) VALUES ('BUS-99',SYSTIMESTAMP,'REJECT','UNKNOWN_BUS')]');

  -- from here on we check the demo data: reload it fresh
  pkg_bus_tracker.refresh_demo_locations;

  DBMS_OUTPUT.PUT_LINE('--- T-SEED: demo data ---');
  ok('T-SEED1', 'row counts 7/2/10/20/4/3/11/3',
     cnt('SELECT COUNT(*) FROM stops') = 7 AND cnt('SELECT COUNT(*) FROM routes') = 2
     AND cnt('SELECT COUNT(*) FROM route_stops') = 10 AND cnt('SELECT COUNT(*) FROM route_points') = 20
     AND cnt('SELECT COUNT(*) FROM buses') = 4 AND cnt('SELECT COUNT(*) FROM bus_locations') = 3
     AND cnt('SELECT COUNT(*) FROM system_config') = 11 AND cnt('SELECT COUNT(*) FROM demo_location_template') = 3);
  ok('T-SEED2', 'route totals equal the sum of segment distances',
     cnt('SELECT COUNT(*) FROM routes r WHERE r.total_length_m <> (SELECT SUM(distance_to_next_m) FROM route_stops s WHERE s.route_id = r.route_id)') = 0);
  ok('T-SEED3', 'cumulative(n+1) = cumulative(n) + distance_to_next(n)',
     cnt('SELECT COUNT(*) FROM (SELECT cumulative_distance_m c, distance_to_next_m d, LEAD(cumulative_distance_m) OVER (PARTITION BY route_id ORDER BY stop_sequence) nc FROM route_stops) WHERE nc IS NOT NULL AND nc <> c + d') = 0);
  ok('T-SEED4', 'stop sequences are 1..n without gaps',
     cnt('SELECT COUNT(*) FROM (SELECT route_id FROM route_stops GROUP BY route_id HAVING MIN(stop_sequence) <> 1 OR MAX(stop_sequence) <> COUNT(*))') = 0);
  ok('T-SEED5', 'first stop of every route has cumulative distance 0',
     cnt('SELECT COUNT(*) FROM route_stops WHERE stop_sequence = 1 AND cumulative_distance_m <> 0') = 0);
  ok('T-SEED6', 'route_points cumulative distance matches route_stops at every stop',
     cnt('SELECT COUNT(*) FROM route_points p JOIN route_stops s ON s.route_id = p.route_id AND s.stop_id = p.stop_id WHERE p.cumulative_distance_m <> s.cumulative_distance_m') = 0);
  ok('T-SEED7', 'every stop point on a path belongs to that route',
     cnt('SELECT COUNT(*) FROM route_points p WHERE p.stop_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM route_stops s WHERE s.route_id = p.route_id AND s.stop_id = p.stop_id)') = 0);
  ok('T-SEED8', 'path cumulative distance strictly increases',
     cnt('SELECT COUNT(*) FROM (SELECT cumulative_distance_m c, LEAD(cumulative_distance_m) OVER (PARTITION BY route_id ORDER BY point_seq) nc FROM route_points) WHERE nc IS NOT NULL AND nc <= c') = 0);
  ok('T-SEED9', 'all stops inside the service-area box',
     cnt(q'[SELECT COUNT(*) FROM stops WHERE latitude NOT BETWEEN (SELECT config_value FROM system_config WHERE config_key='bbox_min_lat') AND (SELECT config_value FROM system_config WHERE config_key='bbox_max_lat') OR longitude NOT BETWEEN (SELECT config_value FROM system_config WHERE config_key='bbox_min_lng') AND (SELECT config_value FROM system_config WHERE config_key='bbox_max_lng')]') = 0);
  ok('T-SEED10','everything labelled DEMO / SIMULATED',
     cnt(q'[SELECT COUNT(*) FROM stops WHERE data_origin <> 'DEMO']') + cnt(q'[SELECT COUNT(*) FROM routes WHERE data_origin <> 'DEMO']')
     + cnt(q'[SELECT COUNT(*) FROM buses WHERE data_origin <> 'DEMO']') + cnt(q'[SELECT COUNT(*) FROM bus_locations WHERE data_source <> 'SIMULATED']') = 0);

  DBMS_OUTPUT.PUT_LINE('--- T-VIEW: status view ---');
  ok('T-VIEW1', 'BUS-01 ACTIVE / LIVE (age ~5 s)',
     cnt(q'[SELECT COUNT(*) FROM v_bus_status WHERE bus_id='BUS-01' AND display_status='ACTIVE' AND data_freshness='LIVE']') = 1);
  ok('T-VIEW2', 'BUS-02 OFFLINE (age ~600 s)',
     cnt(q'[SELECT COUNT(*) FROM v_bus_status WHERE bus_id='BUS-02' AND display_status='OFFLINE' AND data_freshness='OFFLINE']') = 1);
  ok('T-VIEW3', 'BUS-03 NOT_IN_SERVICE / UNAVAILABLE (no location)',
     cnt(q'[SELECT COUNT(*) FROM v_bus_status WHERE bus_id='BUS-03' AND display_status='NOT_IN_SERVICE' AND data_freshness='UNAVAILABLE' AND age_seconds IS NULL]') = 1);
  ok('T-VIEW4', 'BUS-04 STALE (age ~60 s)',
     cnt(q'[SELECT COUNT(*) FROM v_bus_status WHERE bus_id='BUS-04' AND display_status='STALE' AND data_freshness='STALE']') = 1);
  ok('T-VIEW5', 'view and package give the same freshness and status',
     cnt('SELECT COUNT(*) FROM v_bus_status WHERE data_freshness <> pkg_bus_tracker.freshness(age_seconds) OR display_status <> pkg_bus_tracker.display_status(service_state, data_freshness)') = 0);
  ok('T-VIEW6', 'timestamp_iso is strict ISO 8601 UTC with Z',
     cnt(q'[SELECT COUNT(*) FROM v_bus_status WHERE timestamp_iso IS NOT NULL AND NOT REGEXP_LIKE(timestamp_iso, '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')]') = 0);

  DBMS_OUTPUT.PUT_LINE('--- end-to-end: live update turns STALE bus LIVE ---');
  pkg_bus_tracker.apply_location_update(
    p_bus_id => 'BUS-04', p_latitude => 4.3872, p_longitude => 100.9743,
    p_timestamp => pkg_bus_tracker.to_iso_utc(SYS_EXTRACT_UTC(SYSTIMESTAMP)),
    p_outcome => v_o, p_reason => v_r, p_data_source => 'SIMULATED');
  ok('E2E1', 'real-clock update accepted (' || v_o || '/' || v_r || ')', v_o = 'ACCEPT' AND v_r = 'OK');
  ok('E2E2', 'BUS-04 is now ACTIVE',
     cnt(q'[SELECT COUNT(*) FROM v_bus_status WHERE bus_id='BUS-04' AND display_status='ACTIVE']') = 1);

  -- leave the database in a clean demo state
  pkg_bus_tracker.refresh_demo_locations;

  DBMS_OUTPUT.PUT_LINE('=====================================================');
  DBMS_OUTPUT.PUT_LINE(g_pass || ' passed, ' || g_fail || ' failure(s)');
  IF g_fail = 0 THEN
    DBMS_OUTPUT.PUT_LINE('ALL TESTS PASSED - demo data reloaded.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('SOME TESTS FAILED - read the FAIL lines above.');
  END IF;
END;
/
