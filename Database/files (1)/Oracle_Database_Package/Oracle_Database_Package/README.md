# Smart Campus Bus Tracker - Database package (Oracle edition v1.2)
Owner: Roy (Person 3). ALL DATA IS DEMO / SIMULATED.

Quick start (Oracle XE 21c)
1. As SYSTEM: `@oracle/00_create_users.sql`  (change the passwords first)
2. As BUS_OWNER, inside the oracle folder: `@install_all.sql`
3. As BUS_OWNER: `@05_tests.sql`  -> expect ALL TESTS PASSED
4. Before every demo: `EXEC pkg_bus_tracker.refresh_demo_locations;`

No Oracle needed: `python3 tests/test_data_quality.py` (62 checks).
Full guide: Database_Documentation_Oracle_v1.2.docx (Part 4).
