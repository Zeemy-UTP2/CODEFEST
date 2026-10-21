-- =====================================================================
-- install_all.sql  -  build the whole demo database in one go.
-- Run as BUS_OWNER, from THIS folder:
--     cd oracle
--     sqlplus bus_owner/<password>@localhost:1521/XEPDB1 @install_all.sql
-- (In SQL Developer: open this folder as the working directory, or run
--  01..04 one by one with "Run Script" (F5).)
-- To start from zero first run 99_drop_all.sql.
-- =====================================================================
SET ECHO OFF
SET DEFINE OFF
SET SQLBLANKLINES ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

@01_schema.sql
@02_package.sql
@03_seed.sql
@04_grants.sql

PROMPT
PROMPT ===== Bus status right now =====
SET LINESIZE 120
COLUMN bus_id         FORMAT A8
COLUMN display_status FORMAT A15
COLUMN data_freshness FORMAT A12
SELECT bus_id, display_status, data_freshness, age_seconds FROM v_bus_status ORDER BY bus_id;
PROMPT Expected: BUS-01 ACTIVE/LIVE, BUS-02 OFFLINE, BUS-03 NOT_IN_SERVICE/UNAVAILABLE, BUS-04 STALE
