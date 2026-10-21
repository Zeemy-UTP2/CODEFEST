# Smart Campus Bus Tracker — CodeFest'26

A mobile-first web app that shows campus buses on a live map, says whether each bus's location is current, and estimates when a bus will reach your stop.

The project uses no AI or machine learning. Its "smart" parts are rule-based: GPS validation, freshness thresholds, and route-aware distance and ETA calculations.

> **Demo data.** Stops, routes and bus positions are demo or simulated values, and every one is labelled as such in the app. This is not a real live UTP service.

## Team

| Member | Role | Main files |
|---|---|---|
| Keanu | Frontend and UI/UX | `static/index.html`, Figma design |
| Hazeem | Backend and API | `main.py`, `store.py`, `traccar_sync.py` |
| Roy | Database and data management | `database/` (Oracle schema, rules package, seed data, tests) |
| Wafiy | GPS, ETA and integration | `simulate.py`, Traccar setup, ETA rules in `rules.py` |

## How it works

```
GPS source ──────────────┐
 • phone running Traccar │      POST /api/locations         ┌───────────────────────┐
 • simulate.py           ├────────────────────────────────▶ │  Backend API          │
                         │                                  │  (Python, FastAPI)    │
                         │                                  │  main.py              │
                                                            └──────────┬────────────┘
                                                                       │ validation + storage
                                                     ┌─────────────────┴─────────────────┐
                                                     │ Oracle database (Roy)             │
                                                     │  pkg_bus_tracker, v_bus_status    │
                                                     │ — or local copy of the same data  │
                                                     └─────────────────┬─────────────────┘
                                                                       │ GET /api/...
                                                            ┌──────────▼────────────┐
                                                            │ Student web app       │
                                                            │ static/index.html     │
                                                            └───────────────────────┘
```

- **Validation.** Every GPS update goes through Roy's rules in the same order:
  - missing fields, unknown bus, coordinates out of range or outside the service area
  - a bad, future, duplicate or older timestamp
  - an impossible jump in position

  Each rejection gets a reason code, and every outcome is logged.
- **Freshness.** A position is `LIVE` for up to 30 s, `STALE` up to 120 s, then `OFFLINE`, using Roy's `system_config` values. A bus is never called "delayed", because there is no timetable to prove it.
- **ETA.** The bus position is projected onto the route path and the distance along the route to the stop is measured. That distance is divided by the bus's speed, or by a 20 km/h average when the bus is barely moving. ETAs are labelled as estimates. When a position is stale, the ETA is marked approximate; when the bus is offline, no ETA is shown.
- **Two data modes.**
  - **Oracle mode** (`ORACLE_DSN` set): validation runs inside Roy's PL/SQL package, and status comes from his view.
  - **Local mode** (default): a Python copy of the same rules and demo data.

  `test_rules.py` runs Roy's test cases against the Python copy (61 pass), which shows the two modes behave the same.

## Run it (Windows, PowerShell, in VS Code's terminal)

```powershell
cd "C:\Users\Hazeem\Documents\GitHub\CODEFEST"
py -m pip install -r requirements.txt
py -m uvicorn main:app --reload --host 0.0.0.0
```

- **App:** http://127.0.0.1:8000
- **API docs:** http://127.0.0.1:8000/docs

To **make the buses move**, open a second terminal (the **+** in the terminal panel) and run:

```powershell
cd "C:\Users\Hazeem\Documents\GitHub\CODEFEST"
py simulate.py --buses BUS-01 --speed 30
```

To **open the app on your phone**, connect the phone and laptop to the same Wi-Fi or the phone's hotspot. Find the laptop's IP address with `ipconfig` (look for "IPv4 Address", for example `192.168.1.23`), then open `http://192.168.1.23:8000` on the phone. If Windows asks about the firewall, allow access.

To **reset the demo** before recording, run **POST /api/demo/reset** from the `/docs` page.

To **run the rule tests**:

```powershell
py test_rules.py
```

## Optional: Oracle and Traccar

1. Copy `.env.example` to `.env` and fill it in. `.env` is in `.gitignore`, so it never reaches GitHub.
2. **Oracle:**
   1. Roy runs `database/install_all.sql` (see the comments in each file).
   2. Run `py -m pip install -r requirements-oracle.txt`.
   3. Set `ORACLE_DSN`, for example `localhost:1521/XEPDB1`, and the `bus_app` password.
   4. Restart. The app's header chip changes to **Oracle DB**. If the connection fails, the app falls back to local data and says so.
3. **Traccar (your real phone as a bus):**
   1. Set `TRACCAR_EMAIL`, `TRACCAR_PASSWORD` and `TRACCAR_DEVICE_MAP`. The default maps your Traccar device "BUS-01" to bus BUS-04.
   2. Your phone must be inside the campus area, or updates are rejected with `OUTSIDE_SERVICE_AREA`.
   3. `GET /api/health` shows the last Traccar result.
   4. In the Traccar Client app, set the reporting interval to 5–10 s; otherwise the bus will flip to `STALE`.

## API

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/locations` | Submit a GPS update. 200 means ACCEPT, or IGNORE for a duplicate or older update; 400 means REJECT, with a reason code |
| GET | `/api/buses` | All buses with location, age, freshness and status |
| GET | `/api/buses/{busId}` | One bus plus ETAs to every stop on its route |
| GET | `/api/stops` | All stops and the routes serving them |
| GET | `/api/stops/{stopId}/arrivals` | Buses coming to a stop, soonest first |
| GET | `/api/routes` | Routes with ordered stops and map path |
| GET | `/api/health` | Mode (oracle or local) and Traccar status |
| GET | `/api/log` | Latest updates and their outcomes |
| POST | `/api/demo/reset` | Reload the demo positions |

## Limitations

- **Demo data:** coordinates are approximate and not surveyed, and buses are simulated unless a Traccar phone is connected. Real use needs approval from the university and transport office before collecting driver location.
- **ETAs** are distance divided by speed, with no traffic or timetable data.
- **The web app is a prototype.** It has no login and no admin screens.
- **Oracle mode** is written against Roy's schema and package but was only tested here in local mode. Run it once against the real database before relying on it.
