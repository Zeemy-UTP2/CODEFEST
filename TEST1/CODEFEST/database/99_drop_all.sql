-- =====================================================================
-- 99_drop_all.sql  -  FULL RESET: removes every table, view and package
-- in the BUS_OWNER schema. Then run install_all.sql again.
-- Run as BUS_OWNER ONLY. (Do not run in a schema that holds other work.)
-- For a quick pre-demo refresh you do NOT need this - use:
--     EXEC pkg_bus_tracker.refresh_demo_locations;
-- =====================================================================
SET DEFINE OFF
SET SQLBLANKLINES ON
BEGIN
  FOR v IN (SELECT view_name FROM user_views) LOOP
    EXECUTE IMMEDIATE 'DROP VIEW "' || v.view_name || '"';
  END LOOP;
  FOR p IN (SELECT object_name FROM user_objects WHERE object_type = 'PACKAGE') LOOP
    EXECUTE IMMEDIATE 'DROP PACKAGE "' || p.object_name || '"';
  END LOOP;
  FOR t IN (SELECT table_name FROM user_tables) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/
PROMPT Schema cleared. Now run install_all.sql
