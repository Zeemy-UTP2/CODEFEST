-- =====================================================================
-- 04_grants.sql  -  least-privilege access (run as BUS_OWNER)
--
--                     reference   bus_locations   location_log   system_config  package
--   BUS_APP (backend)   read        read            read           read          EXECUTE
--   BUS_READONLY        read        read            -              read          -
--   BUS_OWNER (Roy)     everything (reseed / maintain)
--
-- Nobody except BUS_OWNER can INSERT/UPDATE/DELETE tables directly. The
-- backend writes locations ONLY through pkg_bus_tracker.apply_location_update.
-- The student app never gets a database login at all: it talks to the
-- backend API (see docs, "Architecture with Oracle").
-- =====================================================================
SET DEFINE OFF

GRANT SELECT ON stops          TO bus_app, bus_readonly;
GRANT SELECT ON routes         TO bus_app, bus_readonly;
GRANT SELECT ON route_stops    TO bus_app, bus_readonly;
GRANT SELECT ON route_points   TO bus_app, bus_readonly;
GRANT SELECT ON buses          TO bus_app, bus_readonly;
GRANT SELECT ON bus_locations  TO bus_app, bus_readonly;
GRANT SELECT ON system_config  TO bus_app, bus_readonly;
GRANT SELECT ON v_route_stops  TO bus_app, bus_readonly;
GRANT SELECT ON v_bus_status   TO bus_app, bus_readonly;

GRANT SELECT ON location_log   TO bus_app;       -- debugging only
GRANT EXECUTE ON pkg_bus_tracker TO bus_app;

PROMPT 04_grants.sql done.
