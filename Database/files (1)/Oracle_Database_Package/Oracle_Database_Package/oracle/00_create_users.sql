-- =====================================================================
-- Smart Campus Bus Tracker | CodeFest'26 | Oracle edition (v1.2)
-- 00_create_users.sql  -  run ONCE, connected as SYSTEM (or SYS as SYSDBA)
--
-- Oracle XE 21c keeps user data in a pluggable database called XEPDB1.
-- Users are created THERE, not in the root container (CDB$ROOT).
--
-- Three accounts (least privilege, see docs "Access and permissions"):
--   BUS_OWNER    owns every table/view/package. Roy + admin tasks only.
--   BUS_APP      used by the BACKEND (Hazeem). Can read, and call the
--                package. Cannot write to tables directly.
--   BUS_READONLY read-only (teammates, demos, ORDS/REST read endpoints).
--
-- CHANGE THE PASSWORDS before you share this file or push it to GitHub.
-- Never commit real passwords.
-- =====================================================================
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

ALTER SESSION SET CONTAINER = XEPDB1;

CREATE USER bus_owner    IDENTIFIED BY "Change_Me_Owner_1"
  DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
CREATE USER bus_app      IDENTIFIED BY "Change_Me_App_1";
CREATE USER bus_readonly IDENTIFIED BY "Change_Me_Read_1";

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE,
      CREATE TRIGGER, CREATE SEQUENCE                       TO bus_owner;
GRANT CREATE SESSION                                        TO bus_app;
GRANT CREATE SESSION                                        TO bus_readonly;

-- Object privileges for BUS_APP / BUS_READONLY are granted by
-- 04_grants.sql (run as BUS_OWNER after the schema exists).

PROMPT Users created in XEPDB1. Next: connect as BUS_OWNER and run install_all.sql
