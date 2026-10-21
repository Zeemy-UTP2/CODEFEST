// Builds Database_Documentation_Oracle_v1.2.docx   (node scripts/make_doc.js)
const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, ImageRun, Footer,
  AlignmentType, LevelFormat, HeadingLevel, BorderStyle, WidthType, ShadingType,
  PageOrientation, PageNumber, PageBreak,
} = require("docx");

const ROOT = path.resolve(__dirname, "..");
const OUT = process.argv[2] || path.join(ROOT, "Database_Documentation_Oracle_v1.2.docx");
const erd = fs.readFileSync(path.join(ROOT, "docs", "erd.png"));

const W = 9638;                       // A4 portrait content width (DXA)
const SLATE = "37474F", BLUE = "1565C0", GREY = "F5F7F8", AMBER = "FFF8E1", GREEN = "E8F5E9", RED = "FDECEA";
const FONT = "Calibri", MONO = "Consolas";

// ---------- inline markup: **bold**  `code` ----------
function runs(text, base = {}) {
  const out = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`)/g;
  let last = 0, m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push(new TextRun({ text: text.slice(last, m.index), font: FONT, ...base }));
    const tok = m[0];
    if (tok.startsWith("**")) out.push(new TextRun({ text: tok.slice(2, -2), bold: true, font: FONT, ...base }));
    else out.push(new TextRun({ text: tok.slice(1, -1), font: MONO, size: (base.size || 21) - 2, ...base, color: base.color || "B71C1C" }));
    last = m.index + tok.length;
  }
  if (last < text.length) out.push(new TextRun({ text: text.slice(last), font: FONT, ...base }));
  return out;
}

const P = (text, o = {}) => new Paragraph({ children: runs(text, o.run || {}), spacing: { after: o.after ?? 100, before: o.before ?? 0, line: 270 }, alignment: o.align, keepNext: o.keepNext, indent: o.indent });
const H1 = (t, pageBreak = true) => new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: pageBreak, children: [new TextRun({ text: t, font: FONT })] });
const H2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, keepNext: true, children: [new TextRun({ text: t, font: FONT })] });
const H3 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_3, keepNext: true, children: [new TextRun({ text: t, font: FONT })] });
const B = (text, level = 0) => new Paragraph({ numbering: { reference: "bul", level }, children: runs(text), spacing: { after: 60, line: 264 } });
const N = (text, ref = "num") => new Paragraph({ numbering: { reference: ref, level: 0 }, children: runs(text), spacing: { after: 70, line: 264 } });

function code(lines) {
  return lines.map((l, i) => new Paragraph({
    children: [new TextRun({ text: l === "" ? " " : l, font: MONO, size: 17 })],
    shading: { type: ShadingType.CLEAR, fill: "ECEFF1" },
    spacing: { after: 0, line: 240, before: i === 0 ? 60 : 0 },
    indent: { left: 120, right: 120 },
    keepLines: true,
  })).concat([new Paragraph({ children: [], spacing: { after: 80 } })]);
}

const bd = { style: BorderStyle.SINGLE, size: 4, color: "B0BEC5" };
const borders = { top: bd, bottom: bd, left: bd, right: bd };
function cell(text, width, o = {}) {
  const paras = String(text).split("\n").map((t) => new Paragraph({ children: runs(t, { size: o.size || 18, bold: o.bold, color: o.color }), spacing: { after: 20, line: 244 } }));
  return new TableCell({
    width: { size: width, type: WidthType.DXA }, borders,
    shading: o.fill ? { type: ShadingType.CLEAR, fill: o.fill, color: "auto" } : undefined,
    margins: { top: 50, bottom: 50, left: 90, right: 90 }, children: paras,
  });
}
function tbl(headers, rows, widths, o = {}) {
  const total = widths.reduce((a, b) => a + b, 0);
  const head = new TableRow({ tableHeader: true, cantSplit: true, children: headers.map((h, i) => cell(h, widths[i], { fill: SLATE, color: "FFFFFF", bold: true })) });
  const body = rows.map((r) => new TableRow({ cantSplit: true, children: r.map((c, i) => cell(c, widths[i], { fill: o.firstColFill && i === 0 ? GREY : undefined })) }));
  return [new Table({ width: { size: total, type: WidthType.DXA }, columnWidths: widths, rows: [head, ...body] }), new Paragraph({ children: [], spacing: { after: 100 } })];
}
function box(text, fill = AMBER, bar = "F9A825") {
  const lines = Array.isArray(text) ? text : [text];
  const b = { style: BorderStyle.SINGLE, size: 4, color: "FFFFFF" };
  return [new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: [W],
    rows: [new TableRow({ children: [new TableCell({
      width: { size: W, type: WidthType.DXA },
      borders: { top: b, bottom: b, right: b, left: { style: BorderStyle.SINGLE, size: 24, color: bar } },
      shading: { type: ShadingType.CLEAR, fill, color: "auto" }, margins: { top: 90, bottom: 90, left: 160, right: 140 },
      children: lines.map((t) => new Paragraph({ children: runs(t, { size: 20 }), spacing: { after: 50, line: 262 } })),
    })] })],
  }), new Paragraph({ children: [], spacing: { after: 100 } })];
}

// =====================================================================
const c = []; // content of the portrait section
// ---------- Title block ----------
c.push(new Paragraph({ spacing: { before: 600, after: 60 }, children: [new TextRun({ text: "Smart Campus Bus Tracker", font: FONT, size: 56, bold: true, color: SLATE })] }));
c.push(new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: "Database and Data Management Documentation", font: FONT, size: 36, color: BLUE })] }));
c.push(new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: "ORACLE EDITION", font: FONT, size: 26, bold: true, color: "C62828" })] }));
c.push(new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: "Roy - Person 3 | CodeFest'26 - CivicTech & Public Services", font: FONT, size: 22, color: "546E7A" })] }));
c.push(new Paragraph({ spacing: { after: 200 }, border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: "B0BEC5", space: 6 } }, children: [new TextRun({ text: "Version 1.2 - October 2026 (replaces v1.1 SQLite/Firestore edition)", font: FONT, size: 22, color: "546E7A" })] }));
c.push(...box("**All data described here is DEMO / SIMULATED.** Stop coordinates are approximate placeholders, not surveyed UTP bus stops, and simulated positions are not a real live service."));
c.push(P("**Contents:** Part 1 Overview and ERD - Part 2 Data Dictionary and Data Requirements - Part 3 Data Quality Rules and Test Cases - Part 4 Oracle Setup, Reset and Access Guide - Part 5 Technology Decision: Oracle and the Backend."));

// =====================================================================
c.push(H1("Part 1 - Overview and Entity Relationship Diagram", false));
c.push(P("CodeFest'26 | Owner: Roy (Person 3) | Version 1.2 (Oracle)"));
c.push(H2("1.1 Can the project run on Oracle? Yes."));
c.push(...box([
  "**Yes.** Oracle Database XE (Express Edition) is free, runs on a laptop, and is more than enough for this project (about 60 rows of reference data, one live row per bus). The whole database design, the demo data, the data-quality rules and the tests have been rebuilt for Oracle in this version.",
  "**One thing changes for the team:** the Flutter app cannot (and must not) connect to Oracle directly. It talks to a small **backend API** (Hazeem), and only the backend talks to Oracle. The blueprint allowed 'a separate server only if needed' - with Oracle it is needed. Details in Part 5.",
], GREEN, "2E7D32"));
c.push(H2("1.2 Quick start"));
c.push(...code([
  "-- 1. As SYSTEM (once):               @00_create_users.sql",
  "-- 2. As BUS_OWNER, in folder oracle:  @install_all.sql        (schema + package + demo data)",
  "-- 3. As BUS_OWNER:                    @05_tests.sql           (117 database checks)",
  "-- Before every demo:                  EXEC pkg_bus_tracker.refresh_demo_locations;",
  "",
  "python3 tests/test_data_quality.py     # 62 reference checks, no Oracle needed",
]));
c.push(P("Full step-by-step instructions are in Part 4."));
c.push(H2("1.3 What changed from v1.1 (SQLite) to v1.2 (Oracle)"));
c.push(...tbl(["Area", "v1.1", "v1.2 - Oracle"], [
  ["Production database", "Firestore recommended; SQLite only as a reference", "**Oracle XE** (team decision). SQLite and Firestore are no longer used"],
  ["Schema file", "schema.sql", "oracle/01_schema.sql (tables, named constraints, trigger, indexes, views, column comments)"],
  ["Rules engine", "data_quality.py + apply_update.py", "**pkg_bus_tracker** (PL/SQL) inside the database. data_quality.py is kept as the executable specification and as a port source for the backend"],
  ["Timestamps", "TEXT, ISO 8601", "**TIMESTAMP(0), UTC.** The JSON contract is unchanged: views and functions give the same ISO string with trailing Z"],
  ["ID / format rules", "CHECK with GLOB", "CHECK with REGEXP_LIKE (plus a control-character guard)"],
  ["Foreign keys", "PRAGMA foreign_keys = ON on every connection", "Always enforced by Oracle"],
  ["'Older update never wins'", "Conditional upsert + trigger", "Row lock + MERGE ... WHERE newer + trigger (three layers)"],
  ["Loading the demo data", "load_seed.py", "03_seed.sql, generated from seed/seed.json by seed/make_oracle_seed.py"],
  ["Reset before a demo", "python3 load_seed.py", "`EXEC pkg_bus_tracker.refresh_demo_locations;` (1 second) or 99_drop_all.sql + install_all.sql"],
  ["Firestore mapping (old Part 5)", "Table-to-collection mapping, security rules", "Dropped. Firebase may still be used for push notifications (FCM) only; it is independent of the database"],
  ["**New in v1.2**", "-", "route_points.cumulative_distance_m; config key arrival_radius_m; reason code BAD_OPTIONAL_FIELD; function remaining_distance_m (route-aware distance for ETA); table demo_location_template; least-privilege accounts BUS_APP / BUS_READONLY"],
  ["Renamed columns", "sequence; key; value", "stop_sequence; config_key; config_value (SEQUENCE, KEY and VALUE are Oracle keywords). **JSON/API names are unchanged** (sequence, key, value)"],
], [2100, 3200, 4338], { firstColFill: true }));
c.push(H2("1.4 Deliverables (team plan, tasks 5.1 - 5.6)"));
c.push(...tbl(["Task", "Deliverable", "File"], [
  ["5.1 Data requirements", "Requirements list and field definitions", "Part 2, sections 2 - 4 (and column comments inside Oracle)"],
  ["5.2 Database structure", "Schema with rules, ERD, sample records", "oracle/01_schema.sql, docs/erd.png / erd.svg"],
  ["5.3 Sample data", "Labelled seed data and generators", "seed/seed.json, seed/build_seed.py, seed/make_oracle_seed.py, oracle/03_seed.sql"],
  ["5.4 Shared data dictionary", "Conventions, payload, examples, status vocabulary", "Part 2"],
  ["5.5 Data quality rules", "Rules, thresholds, test cases", "Part 3, oracle/02_package.sql, data_quality.py, oracle/05_tests.sql, tests/"],
  ["5.6 Setup and permissions", "Setup / reset guide, access notes", "Part 4, oracle/00_create_users.sql, 04_grants.sql, 99_drop_all.sql"],
  ["Technology decision", "Oracle architecture and backend connection", "Part 5, examples/backend_oracle_example.py"],
  ["Combined submission document", "All of the above in one Word file", "Database_Documentation_Oracle_v1.2.docx (this file)"],
], [2300, 3300, 4038], { firstColFill: true }));
c.push(H2("1.5 Handoffs"));
c.push(...tbl(["To", "What they get", "What Roy needs back"], [
  ["Keanu (frontend)", "Field names and example records (Part 2, sections 6 - 7), status vocabulary, missing-value behaviour", "Which fields each screen needs beyond these"],
  ["Hazeem (backend/API)", "pkg_bus_tracker.apply_location_update (one call per GPS update), views v_bus_status and v_route_stops, examples/backend_oracle_example.py, BUS_APP account", "**Confirmation of the architecture in Part 5** (backend between app and Oracle) and the language/framework chosen"],
  ["Wafiy (GPS / ETA)", "Thresholds in system_config, freshness/status rules, route distances, function remaining_distance_m and the ETA helper", "Confirm update interval, stale/offline thresholds, ETA fallback speed"],
], [1900, 4700, 3038], { firstColFill: true }));
c.push(H2("1.6 Known limits (be honest in the pitch)"));
c.push(B("Stop coordinates and route paths are **demo values**. Distances are straight-line segments between demo points, **not** measured road distances. Do not claim real-world distance or ETA accuracy until stops are surveyed."));
c.push(B("The service-area box and the jump-speed limit are demo values pending a field survey."));
c.push(B("Oracle XE runs on one machine. For the demo the backend and the database should run on the same laptop (or reachable network); this is a prototype set-up, not a production deployment."));
c.push(B("Oracle has no push/listener feature like Firebase listeners. The app **polls** the backend (every 5 s matches the sender interval)."));
c.push(B("Trips, alert preferences and service notices (optional, phase 5) are intentionally not built."));
c.push(H2("1.7 Test run record (fill in before submission)"));
c.push(P("The Python reference suite has been run: **62 of 62 checks pass**. The Oracle script files were syntax-checked (all 55 DDL statements and 57 INSERT statements parse as Oracle SQL) but must be executed once on the team's Oracle XE. Record the result here:"));
c.push(...tbl(["Check", "Command", "Result (fill in)", "Date / by"], [
  ["Installation", "@install_all.sql ends without ORA- errors", "", ""],
  ["Database tests", "@05_tests.sql -> 'ALL TESTS PASSED'", "___ passed, ___ failure(s)", ""],
  ["Reference tests", "python3 tests/test_data_quality.py", "62 passed, 0 failure(s)", ""],
  ["Backend smoke test", "python3 examples/backend_oracle_example.py", "", ""],
], [2200, 3600, 2200, 1638], { firstColFill: true }));

// ---------- ERD (landscape) is a separate section, see below ----------

// =====================================================================
const p2 = [];
p2.push(H1("Part 2 - Data Dictionary and Data Requirements", false));
p2.push(H2("1. Purpose and status"));
p2.push(P("This is the shared data contract for **Keanu (frontend)**, **Hazeem (backend/API)** and **Wafiy (GPS/ETA)**. It answers, for every field: what does it mean, what type is it, where does it come from, and what is the rule? If this document and the code disagree, **oracle/01_schema.sql wins** and this document must be fixed."));
p2.push(...tbl(["Item", "Value"], [
  ["Version", "1.2 (Oracle edition)"],
  ["Owner", "Roy (Person 3)"],
  ["Reference implementation", "oracle/01_schema.sql and oracle/02_package.sql (Oracle Database XE 21c; also works on 18c and 23ai Free)"],
  ["Data status", "**All data in seed/seed.json is DEMO / SIMULATED.** Stop coordinates are approximate placeholders, not surveyed UTP bus stops."],
  ["Look inside the database", "`SELECT * FROM user_col_comments WHERE table_name = 'STOPS';` shows the meaning of every column"],
], [2600, 7038], { firstColFill: true }));

p2.push(H2("2. Data requirements (task 5.1)"));
p2.push(P("Reference data changes rarely and is edited by an admin. Live data changes every few seconds and is written only by the location-update flow. They are stored separately so that frequent GPS writes never touch the stable records."));
p2.push(...tbl(["Group", "Data", "Changes", "Written by", "Source"], [
  ["Reference", "Stops (name, coordinates)", "Rarely", "Admin / seed", "Field survey (to do), or official UTP data"],
  ["Reference", "Routes (name, colour, length, loop flag)", "Rarely", "Admin / seed", "Transport office / team"],
  ["Reference", "Route-stop order and distances", "Rarely", "Admin / seed", "Computed from coordinates, then measured"],
  ["Reference", "Route path points (map polyline) with cumulative distance", "Rarely", "Admin / seed", "Demo: generated. Real: traced on the map"],
  ["Reference", "Buses (label, assigned route, service state)", "Rarely", "Admin / seed", "Transport office"],
  ["Live", "Latest bus location", "Every few seconds", "Database package (after validation)", "GPS sender / simulator"],
  ["Audit", "Location update log", "Every update", "Database package", "Package decision"],
  ["Configuration", "Thresholds (stale, offline, speed limit, ...)", "Rarely", "Team", "Agreed between Roy, Wafiy, Hazeem"],
  ["Optional (not built)", "Trips, alert preferences, service notices", "-", "-", "Phase 5, only after the core works"],
], [1300, 2900, 1200, 2000, 2238]));

p2.push(H2("3. Global conventions"));
p2.push(...tbl(["Topic", "Convention"], [
  ["IDs", "Fixed prefix, upper case. Buses BUS- + digits (BUS-01). Stops STP- + digits (STP-01). Routes RTE- + letters/digits (RTE-A). Nothing else is allowed (no spaces, symbols, lower case, control characters). IDs are never reused."],
  ["Timestamps", "ISO 8601, **UTC**, trailing Z, whole seconds: 2026-10-04T08:30:00Z. In Oracle they are stored as TIMESTAMP(0) in UTC; the API shows the ISO string (view column timestamp_iso, function to_iso_utc). No local time, no offsets such as +08:00. Display in Malaysia time (UTC+8) only in the UI."],
  ["Coordinates", "WGS84 decimal degrees. latitude -90..90, longitude -180..180. Latitude first. (0,0) is never valid. Stored as NUMBER(10,7) (about 1 cm)."],
  ["Distance / speed / ETA", "Metres (_m), km/h (_kmh), minutes (etaMinutes). The unit is in the field name."],
  ["Booleans", "true/false in JSON, **NUMBER(1) 1/0 in Oracle** (works on every Oracle version)."],
  ["Unknown / missing", "null (JSON) / NULL (Oracle). Never 0, '', 'N/A' or -1 for 'unknown'. **Oracle treats an empty string as NULL**, so an empty name is rejected as missing."],
  ["JSON vs Oracle names", "JSON/API uses **camelCase** (busId); Oracle uses **snake_case** (bus_id). The backend does the mapping (table in Part 5). Three columns differ by more than case: stop_sequence = JSON sequence; config_key = key; config_value = value."],
  ["Timestamp field name", "The GPS capture time is called **timestamp** in every JSON/API message. In Oracle the column is location_timestamp, to sit clearly beside received_at. There is no locationTimestamp anywhere."],
  ["Data origin", "DEMO, SURVEYED or OFFICIAL. The UI must show a visible 'demo data' label while anything is DEMO."],
  ["Order", "A route's stops are ordered by stop_sequence (1, 2, 3, ... no gaps). One route = one direction; a return trip is its own route."],
], [2200, 7438], { firstColFill: true }));

p2.push(H2("4. Field definitions"));
p2.push(P("? = may be NULL. PK primary key, FK foreign key."));
p2.push(H3("4.1 stops - known bus stops (reference)"));
p2.push(...tbl(["Column", "JSON name", "Oracle type", "Rule", "Meaning"], [
  ["stop_id PK", "stopId", "VARCHAR2(20)", "STP- + digits", "Stable stop identifier"],
  ["name", "name", "VARCHAR2(100)", "not blank", "Name shown to students"],
  ["latitude", "latitude", "NUMBER(10,7)", "-90..90, not (0,0)", "Stop position"],
  ["longitude", "longitude", "NUMBER(10,7)", "-180..180", "Stop position"],
  ["active", "active", "NUMBER(1)", "0 / 1", "0 = hidden from the app, record kept"],
  ["data_origin", "dataOrigin", "VARCHAR2(10)", "DEMO / SURVEYED / OFFICIAL", "How trustworthy the coordinates are"],
], [1700, 1400, 1700, 2400, 2438]));
p2.push(H3("4.2 routes (reference)"));
p2.push(...tbl(["Column", "JSON name", "Oracle type", "Rule", "Meaning"], [
  ["route_id PK", "routeId", "VARCHAR2(20)", "RTE- + A-Z/0-9", "Route identifier"],
  ["name", "name", "VARCHAR2(100)", "not blank", "Display name"],
  ["description ?", "description", "VARCHAR2(300)", "", "Short description"],
  ["colour_hex", "colourHex", "VARCHAR2(7)", "#RRGGBB", "Line colour on the map"],
  ["is_loop", "isLoop", "NUMBER(1)", "0 / 1", "1 = last stop connects back to the first"],
  ["total_length_m", "totalLengthM", "NUMBER(9)", "> 0", "Length of one full circuit along the route path. **Equals the sum of distance_to_next_m.**"],
  ["active", "active", "NUMBER(1)", "0 / 1", "0 = route not offered"],
  ["data_origin", "dataOrigin", "VARCHAR2(10)", "DEMO / SURVEYED / OFFICIAL", ""],
], [1700, 1400, 1700, 2400, 2438]));
p2.push(H3("4.3 route_stops - ordered stops of a route (reference)"));
p2.push(...tbl(["Column", "JSON name", "Oracle type", "Rule", "Meaning"], [
  ["route_id PK, FK", "routeId", "VARCHAR2(20)", "must exist in routes", "Cascade delete with the route"],
  ["stop_sequence PK", "sequence", "NUMBER(4)", ">= 1, contiguous", "Position in the route"],
  ["stop_id FK", "stopId", "VARCHAR2(20)", "must exist in stops; unique per route", ""],
  ["cumulative_distance_m", "cumulativeDistanceM", "NUMBER(9)", ">= 0; first stop = 0", "Distance along the route path from stop 1 to this stop"],
  ["distance_to_next_m ?", "distanceToNextM", "NUMBER(9)", "> 0", "Distance to the next stop; for the last stop of a loop, back to stop 1"],
], [1900, 1700, 1500, 2300, 2238]));
p2.push(P("Invariants (tested): cumulative(n+1) = cumulative(n) + distance_to_next(n); sum(distance_to_next) = routes.total_length_m; at every stop, route_points.cumulative_distance_m = route_stops.cumulative_distance_m."));
p2.push(H3("4.4 route_points - map polyline of a route (reference)"));
p2.push(...tbl(["Column", "JSON name", "Oracle type", "Rule", "Meaning"], [
  ["route_id PK, FK", "routeId", "VARCHAR2(20)", "", ""],
  ["point_seq PK", "pointSeq", "NUMBER(5)", ">= 1", "Order along the path"],
  ["latitude, longitude", "latitude, longitude", "NUMBER(10,7)", "valid ranges", "Path vertex"],
  ["stop_id ? FK", "stopId", "VARCHAR2(20)", "", "Set when this vertex is a stop; null for plain curve points"],
  ["cumulative_distance_m (new)", "cumulativeDistanceM", "NUMBER(9)", ">= 0, increasing", "Distance along the path from point 1. Makes route-aware ETA possible"],
], [2100, 1700, 1500, 1700, 2638]));
p2.push(P("The demo path points are generated between stops. They are **not verified campus roads**, so distances and ETAs based on them must not be presented as accurate."));
p2.push(H3("4.5 buses (reference)"));
p2.push(...tbl(["Column", "JSON name", "Oracle type", "Rule", "Meaning"], [
  ["bus_id PK", "busId", "VARCHAR2(20)", "BUS- + digits", "Stable bus identifier"],
  ["label", "label", "VARCHAR2(100)", "not blank", "Display name"],
  ["route_id ? FK", "routeId", "VARCHAR2(20)", "must exist, or null", "Currently assigned route (set to NULL if the route is deleted)"],
  ["service_state", "serviceState", "VARCHAR2(20)", "IN_SERVICE / OUT_OF_SERVICE", "Operator-set state (not derived from GPS)"],
  ["data_origin", "dataOrigin", "VARCHAR2(10)", "", ""],
], [1700, 1400, 1700, 2400, 2438]));
p2.push(H3("4.6 bus_locations - latest accepted location (live)"));
p2.push(P("Exactly **one row per bus**. A bus with no row has no location yet (= NO_DATA). Written only by pkg_bus_tracker.apply_location_update."));
p2.push(...tbl(["Column", "JSON name", "Oracle type", "Rule", "Meaning"], [
  ["bus_id PK, FK", "busId", "VARCHAR2(20)", "must exist in buses", ""],
  ["latitude, longitude", "latitude, longitude", "NUMBER(10,7)", "valid ranges, inside service area", "Position"],
  ["location_timestamp", "**timestamp**", "TIMESTAMP(0) UTC", "valid date/time", "When the GPS fix was captured (sender clock)"],
  ["received_at", "receivedAt", "TIMESTAMP(0) UTC", "valid date/time", "When the backend stored it (server clock)"],
  ["speed_kmh ?", "speedKmh", "NUMBER(6,2)", ">= 0", "Reported speed; null if unknown (not 0)"],
  ["accuracy_m ?", "accuracyM", "NUMBER(8,2)", ">= 0", "Reported GPS accuracy"],
  ["data_source", "dataSource", "VARCHAR2(10)", "LIVE / MANUAL / SIMULATED", "Live GPS, hand-entered, or simulator"],
], [1900, 1600, 1700, 2200, 2238]));
p2.push(H3("4.7 location_log - audit trail (optional, trimmed regularly)"));
p2.push(...tbl(["Column", "Oracle type", "Meaning"], [
  ["log_id PK", "NUMBER identity", "Auto number"],
  ["bus_id ?, latitude ?, longitude ?, location_timestamp ?, data_source ?", "VARCHAR2 / NUMBER", "The update as received. Nullable because malformed updates are logged too. location_timestamp is **text** here, exactly as received"],
  ["received_at", "TIMESTAMP(0)", "Server time of the decision"],
  ["outcome", "VARCHAR2(20)", "ACCEPT / IGNORE_DUPLICATE / IGNORE_OLDER / REJECT"],
  ["reason_code", "VARCHAR2(40)", "OK for ACCEPT; otherwise a code from Part 3"],
], [3600, 1900, 4138]));
p2.push(H3("4.8 system_config - shared thresholds"));
p2.push(P("All modules read these values instead of hard-coding their own."));
p2.push(...tbl(["Key", "Value", "Unit", "Meaning"], [
  ["update_interval_s", "5", "s", "Expected interval between GPS updates"],
  ["stale_after_s", "30", "s", "Location older than this is STALE"],
  ["offline_after_s", "120", "s", "Location older than this is OFFLINE"],
  ["max_future_skew_s", "60", "s", "Max seconds a timestamp may be ahead of the server"],
  ["max_jump_speed_kmh", "100", "km/h", "Faster implied movement between two updates = rejected"],
  ["default_avg_speed_kmh", "20", "km/h", "Fallback speed for ETA when live speed is missing"],
  ["arrival_radius_m (new)", "30", "m", "A bus this close to a stop counts as arrived (ETA 0; also the geofence for alerts)"],
  ["bbox_min_lat / max_lat / min_lng / max_lng", "4.34 / 4.43 / 100.92 / 101.02", "deg", "Service-area box; positions outside are rejected. **Demo values - verify.**"],
], [3000, 2000, 700, 3938]));
p2.push(P("Agreed values are proposals until confirmed by Wafiy and Hazeem (see Part 1, section 1.5).", { run: { italics: true } }));
p2.push(H3("4.9 Views and demo helper"));
p2.push(...tbl(["Object", "Purpose"], [
  ["v_route_stops", "Ordered stops of every route with name, coordinates and distances (join of routes, route_stops, stops). Order by route_id, stop_sequence."],
  ["v_bus_status", "One row per bus: latest location, **timestamp_iso**, received_at_iso, age_seconds, **data_freshness** (LIVE/STALE/OFFLINE/UNAVAILABLE) and **display_status** (ACTIVE/STALE/OFFLINE/NO_DATA/NOT_IN_SERVICE). This is what the backend reads for the map."],
  ["demo_location_template", "Demo only: the ages (5 s, 60 s, 600 s) used by pkg_bus_tracker.refresh_demo_locations to re-time the demo locations before every demo."],
], [2600, 7038], { firstColFill: true }));

p2.push(H2("5. Status vocabulary (single source of truth)"));
p2.push(...tbl(["Field", "Values", "Where it comes from"], [
  ["dataFreshness", "LIVE, STALE, OFFLINE, UNAVAILABLE", "Age of location_timestamp vs system_config"],
  ["displayStatus", "ACTIVE, STALE, OFFLINE, NO_DATA, NOT_IN_SERVICE", "Freshness + service_state"],
  ["serviceState", "IN_SERVICE, OUT_OF_SERVICE", "Set by an operator"],
], [2200, 4000, 3438], { firstColFill: true }));
p2.push(P("There is **no DELAYED** value. Delay can only be claimed against a timetable, and no timetable data exists. (Blueprint rule: only claim what the data can establish.)"));

p2.push(H2("6. Shared update payload (GPS sender -> backend)"));
p2.push(...code([
  "{",
  '  "busId": "BUS-01",',
  '  "latitude": 4.3825,',
  '  "longitude": 100.9690,',
  '  "timestamp": "2026-10-04T08:30:00Z",',
  '  "speedKmh": 18.0,',
  '  "accuracyM": 6.0,',
  '  "dataSource": "SIMULATED"',
  "}",
]));
p2.push(P("Required: busId, latitude, longitude, timestamp. Optional: speedKmh, accuracyM, dataSource (default SIMULATED until real GPS is approved). The backend passes these straight into pkg_bus_tracker.apply_location_update. Coordinates here are demo values."));

p2.push(H2("7. Example records"));
p2.push(P("**Stop**"));
p2.push(...code(['{ "stopId": "STP-01", "name": "Main Gate (Demo)", "latitude": 4.379, "longitude": 100.965,', '  "active": true, "dataOrigin": "DEMO" }']));
p2.push(P("**Route stops (first two of RTE-A)**"));
p2.push(...code([
  '{ "routeId": "RTE-A", "sequence": 1, "stopId": "STP-01", "cumulativeDistanceM": 0,   "distanceToNextM": 616 }',
  '{ "routeId": "RTE-A", "sequence": 2, "stopId": "STP-02", "cumulativeDistanceM": 616, "distanceToNextM": 410 }',
]));
p2.push(P("**Bus and its latest location (as the backend returns it from v_bus_status)**"));
p2.push(...code([
  '{ "busId": "BUS-01", "label": "Demo Bus 1", "routeId": "RTE-A", "serviceState": "IN_SERVICE", "dataOrigin": "DEMO",',
  '  "latitude": 4.3825, "longitude": 100.969, "timestamp": "2026-10-04T08:29:55Z",',
  '  "receivedAt": "2026-10-04T08:30:00Z", "speedKmh": 18.0, "accuracyM": 6.0, "dataSource": "SIMULATED",',
  '  "ageSeconds": 5, "dataFreshness": "LIVE", "displayStatus": "ACTIVE" }',
]));
p2.push(P("**Missing-value behaviour (what each module must do)**"));
p2.push(...tbl(["Situation", "Data", "Required behaviour"], [
  ["Bus never reported", "no bus_locations row", "dataFreshness = UNAVAILABLE, displayStatus = NO_DATA; no marker, no ETA"],
  ["speedKmh null", "NULL", "ETA uses default_avg_speed_kmh and labels it a rough estimate"],
  ["Bus has no route", "route_id NULL", "Show the bus without route info; no ETA"],
  ["Out of service", "service_state = OUT_OF_SERVICE", "NOT_IN_SERVICE whatever the GPS says"],
  ["Stop inactive", "active = 0", "Hide from the app; keep the row"],
], [2200, 2800, 4638], { firstColFill: true }));

p2.push(H2("8. Demo dataset contents"));
p2.push(...tbl(["Table", "Rows", "Notes"], [
  ["stops", "7", "STP-01..STP-07"],
  ["routes", "2", "RTE-A Residential Loop (6 stops, 4334 m), RTE-B Academic Shuttle (4 stops, 2951 m); both loops; share STP-01..03 (a transfer case)"],
  ["route_stops", "10", ""],
  ["route_points", "20", "12 for RTE-A, 8 for RTE-B, each with cumulative distance"],
  ["buses", "4", "BUS-01 live, BUS-02 offline, BUS-03 out of service, BUS-04 stale"],
  ["bus_locations", "3", "ages 5 s (LIVE), 60 s (STALE), 600 s (OFFLINE); BUS-03 intentionally none"],
  ["system_config", "11", ""],
  ["demo_location_template", "3", "Ages used to re-time the demo locations"],
], [2400, 900, 6338], { firstColFill: true }));

// =====================================================================
const p3 = [];
p3.push(H1("Part 3 - Data Quality Rules and Test Cases", false));
p3.push(H2("1. Principle"));
p3.push(P("**Never show old or invalid data as if it were live.** Every location is checked on arrival, every outcome is recorded, and the app decides what to show from the *age* of the last accepted location."));
p3.push(P("With Oracle, the rules live **inside the database** in the package `pkg_bus_tracker` (file 02_package.sql), so every backend language gets the same behaviour. data_quality.py contains the identical rules in Python as the executable specification. Every rule has automated tests (section 6)."));

p3.push(H2("2. Handling an incoming location update"));
p3.push(P("Checks run **in this order**; the first failure decides the outcome."));
p3.push(...tbl(["#", "Code", "Outcome", "Condition", "Where checked"], [
  ["1", "MALFORMED_PAYLOAD", "REJECT", "Payload is not a JSON object", "Backend, then pkg.log_reject"],
  ["2", "MISSING_FIELD", "REJECT", "busId, latitude, longitude or timestamp missing or null", "Database"],
  ["3", "BAD_TYPE", "REJECT", "Coordinates not finite numbers (strings, NaN, booleans), or busId not text", "Backend, then pkg.log_reject"],
  ["3a", "BAD_OPTIONAL_FIELD (new)", "REJECT", "dataSource not LIVE/MANUAL/SIMULATED, or negative speedKmh / accuracyM", "Database"],
  ["4", "UNKNOWN_BUS", "REJECT", "busId is not in buses", "Database"],
  ["5", "OUT_OF_RANGE", "REJECT", "Latitude outside -90..90 or longitude outside -180..180", "Database"],
  ["6", "OUTSIDE_SERVICE_AREA", "REJECT", "Valid coordinates but outside the service-area box (includes (0,0))", "Database"],
  ["7", "BAD_TIMESTAMP", "REJECT", "Not strict YYYY-MM-DDTHH:MM:SSZ UTC, or not a real date/time", "Database"],
  ["8", "FUTURE_TIMESTAMP", "REJECT", "More than max_future_skew_s (60 s) ahead of the server clock", "Database"],
  ["9", "DUPLICATE_TIMESTAMP", "IGNORE_DUPLICATE", "Same timestamp as the stored location", "Database"],
  ["10", "OLDER_THAN_STORED", "IGNORE_OLDER", "Older than the stored location", "Database"],
  ["11", "IMPLAUSIBLE_JUMP", "REJECT", "Implied speed from the stored position exceeds max_jump_speed_kmh (movement under 50 m is GPS noise and never rejected)", "Database"],
  ["-", "OK", "ACCEPT", "All checks passed", "Database"],
], [500, 2200, 1500, 3500, 1938]));
p3.push(P("**Only ACCEPT changes bus_locations.** All outcomes (accepted and rejected) are written to location_log. Rules 1 and 3 are about JSON types: Oracle bind variables are already typed, so the backend checks them first and records them with `pkg_bus_tracker.log_reject`."));
p3.push(H3("The 'older update' rule (agree with Hazeem)"));
p3.push(...tbl(["Received", "Do"], [
  ["Valid and **newer** than stored", "Overwrite the latest location"],
  ["Duplicate or **older**", "Do **not** overwrite; log it"],
  ["Invalid", "Do **not** overwrite; log it"],
], [4000, 5638], { firstColFill: true }));
p3.push(P("Protection is layered, because a table definition alone cannot stop a late packet:"));
p3.push(B("**Layer 1 - package checks** (apply_location_update) compare the new timestamp with the stored one. The stored row is locked (`SELECT ... FOR UPDATE`) so two updates for the same bus cannot interleave."));
p3.push(B("**Layer 2 - conditional write:** `MERGE ... WHEN MATCHED THEN UPDATE ... WHERE t.location_timestamp < new timestamp`."));
p3.push(B("**Layer 3 - trigger `trg_bus_locations_no_older`** aborts any direct UPDATE to an older or equal timestamp (error ORA-20001 OLDER_OR_DUPLICATE_TIMESTAMP)."));

p3.push(H2("3. Freshness and status"));
p3.push(P("Age = server time now (UTC) minus location_timestamp. Thresholds are read from system_config."));
p3.push(...tbl(["Age", "dataFreshness", "What the app must show"], [
  ["0 - 30 s (inclusive)", "LIVE", "Normal marker, 'Updated Ns ago'"],
  ["31 - 120 s (inclusive)", "STALE", "Greyed marker, 'Last seen HH:MM:SS - not live'"],
  ["over 120 s", "OFFLINE", "'Offline - last seen HH:MM:SS'; no ETA"],
  ["no record", "UNAVAILABLE", "No marker: 'No location yet'"],
], [2600, 2200, 4838], { firstColFill: true }));
p3.push(...tbl(["serviceState", "freshness", "displayStatus"], [
  ["OUT_OF_SERVICE", "any", "NOT_IN_SERVICE"],
  ["IN_SERVICE", "LIVE", "ACTIVE"],
  ["IN_SERVICE", "STALE", "STALE"],
  ["IN_SERVICE", "OFFLINE", "OFFLINE"],
  ["IN_SERVICE", "UNAVAILABLE", "NO_DATA"],
], [3200, 3200, 3238]));
p3.push(B("The exact last-update time must always be visible to the user."));
p3.push(B("Clock note: age is measured from the GPS capture time. The 60 s future-skew limit catches a sender clock that runs ahead; a sender clock that runs far behind will simply look STALE, which is the safe direction."));
p3.push(B("DELAYED is **not** produced (no timetable). Do not add it without schedule data."));
p3.push(B("ETA is shown only for ACTIVE buses. For STALE buses the app may show the last known ETA only with a clear 'not live' label (frontend decision, agree with Keanu/Wafiy)."));
p3.push(B("The status view and the package functions give identical results (tested, T-VIEW5)."));

p3.push(H2("4. Missing, invalid, old and duplicate data - summary"));
p3.push(...tbl(["Case", "Handling"], [
  ["Missing field or wrong type", "REJECT, logged, stored location unchanged"],
  ["Invalid coordinates (out of range, (0,0), outside area)", "REJECT, logged"],
  ["Bad or future timestamp", "REJECT, logged"],
  ["Old timestamp", "IGNORE_OLDER, logged"],
  ["Duplicate timestamp", "IGNORE_DUPLICATE, logged"],
  ["GPS jump", "REJECT, logged; the next plausible update is accepted"],
  ["Bus silent", "Becomes STALE then OFFLINE by age alone (no job needed)"],
  ["No route data", "Show the bus; no ETA"],
  ["Log growth", "`EXEC pkg_bus_tracker.trim_location_log(24);` deletes rows older than 24 h"],
], [4200, 5438], { firstColFill: true }));

p3.push(H2("5. Database-level integrity rules (enforced by 01_schema.sql)"));
p3.push(...tbl(["Rule", "Oracle mechanism"], [
  ["IDs match BUS- / STP- / RTE- formats exactly (no !, spaces, lower case, empty suffix, newline)", "CHECK with REGEXP_LIKE(..., 'c') and a control-character guard"],
  ["Coordinates in range and not (0,0)", "CHECK"],
  ["Timestamps are real dates/times in UTC", "TIMESTAMP(0) column type; strict ISO text is parsed by pkg_bus_tracker.parse_iso_utc"],
  ["Valid enum values (status, origin, source, outcome)", "CHECK ... IN (...)"],
  ["Every reference points to a real record", "Foreign keys (always on in Oracle; ON DELETE CASCADE / SET NULL where intended)"],
  ["A stop appears once per route; no repeated sequence numbers", "UNIQUE constraint / composite primary key"],
  ["Text must not be blank", "CHECK (TRIM(x) IS NOT NULL). **Note:** Oracle passes a CHECK whose result is NULL, so LENGTH(TRIM(x)) > 0 would let blank text through"],
  ["Positive distances", "CHECK"],
  ["One latest location per bus", "bus_locations.bus_id is the primary key"],
  ["Older timestamps cannot overwrite newer", "Trigger + conditional MERGE + package logic"],
  ["Log rows are consistent (ACCEPT <-> reason OK)", "CHECK"],
  ["Named constraints", "Every error message names the broken rule, e.g. ORA-02290: check constraint (BUS_OWNER.CK_STOPS_LAT) violated"],
], [4800, 4838]));

p3.push(H2("6. Test cases"));
p3.push(P("Where the tests live: **tests/test_data_quality.py** (Python, no Oracle needed; 62 checks, all pass) and **oracle/05_tests.sql** (inside Oracle; 117 checks). The case IDs below are used in both."));
p3.push(H3("6.1 Location update validation (V)"));
p3.push(...tbl(["ID", "Case", "Expected"], [
  ["V01", "Valid newer update", "ACCEPT / OK"],
  ["V02", "First ever update for a bus", "ACCEPT / OK"],
  ["V03 - V05", "Missing busId / missing timestamp / null latitude", "REJECT / MISSING_FIELD"],
  ["V06, V07", "Latitude as string '4.38' / latitude NaN", "REJECT / BAD_TYPE (backend + log_reject)"],
  ["V08", "Unknown bus BUS-99", "REJECT / UNKNOWN_BUS"],
  ["V09, V10", "Latitude 91 / longitude -181", "REJECT / OUT_OF_RANGE"],
  ["V11, V12", "(0,0) / valid coordinates far away (Kuala Lumpur)", "REJECT / OUTSIDE_SERVICE_AREA"],
  ["V13, V14", "Timestamp 04/10/2026 08:30 / timestamp without Z", "REJECT / BAD_TIMESTAMP"],
  ["V13b, V13c", "Impossible date 2026-02-30 / trailing newline", "REJECT / BAD_TIMESTAMP"],
  ["V15", "Timestamp 10 minutes in the future", "REJECT / FUTURE_TIMESTAMP"],
  ["V16", "Timestamp 30 s in the future (clock skew)", "ACCEPT"],
  ["V17", "Same timestamp as stored", "IGNORE_DUPLICATE"],
  ["V18", "Older than stored", "IGNORE_OLDER"],
  ["V19", "About 5 km in 10 s", "REJECT / IMPLAUSIBLE_JUMP"],
  ["V20", "Payload is a string", "REJECT / MALFORMED_PAYLOAD (backend + log_reject)"],
  ["V21", "Small GPS jitter under 50 m", "ACCEPT"],
  ["V22, V23", "Bad dataSource / negative speed", "REJECT / BAD_OPTIONAL_FIELD"],
  ["V24", "dataSource omitted", "ACCEPT (defaults to SIMULATED)"],
  ["V25, V26", "log_reject refuses other codes / rejected and older updates leave the stored row untouched", "ORA-20020 / unchanged"],
], [1400, 4800, 3438], { firstColFill: true }));
p3.push(H3("6.2 Freshness, status, ETA helper, route distance"));
p3.push(...tbl(["ID", "Case", "Expected"], [
  ["F01 - F06", "Ages 5 s / 30 s / 31 s / 120 s / 121 s / 1 day", "LIVE / LIVE / STALE / STALE / OFFLINE / OFFLINE"],
  ["F07, F08", "No timestamp / garbage timestamp", "UNAVAILABLE"],
  ["S01 - S06", "Every service-state x freshness combination", "See table in section 3"],
  ["E01 - E07", "1000 m at 20 km/h; zero, negative or missing speed; missing or negative distance; 0 m", "3.0; NULL; NULL; NULL; NULL; NULL; 0.0"],
  ["R01", "Loop wrap-around: bus at STP-06, target STP-01", "2027 m"],
  ["R02, R04", "Bus before the stop: STP-01 -> STP-03 / STP-02 -> STP-03", "1026 m / 410 m"],
  ["R03, R07", "Bus at the stop / 10 m past the stop (inside arrival_radius_m)", "0"],
  ["R05, R06", "Non-loop route: bus already past the stop / before the stop", "NULL / 616 m"],
  ["R08, R10", "Stop not on this route / unknown route", "NULL"],
], [1400, 4800, 3438], { firstColFill: true }));
p3.push(H3("6.3 Database behaviour (T) - oracle/05_tests.sql"));
p3.push(...tbl(["Group", "What is proved"], [
  ["T-ID", "Rejected: RTE-A!, RTE-, RTE-a, RTE-A + newline, XYZ-1, STP-01!, STP-A1, BUS-01!, BUS-X1, bus-05. Accepted: RTE-Z9, STP-99, BUS-05"],
  ["T-RNG", "Latitude 91, longitude -181, (0,0), blank and empty names, service state DELAYED, bad colour, bad origin, negative speed, bad data source"],
  ["T-FK", "Unknown route / stop / bus references, duplicate stop on a route, reused sequence, deleting a stop still in use, cascade when a bus is deleted"],
  ["T-OLD", "Trigger blocks older and duplicate direct updates (ORA-20001) and allows a newer one"],
  ["T-LOG", "Log consistency rules; unknown bus IDs can be logged"],
  ["T-SEED", "Row counts; route totals equal segment sums; cumulative distances consistent; sequences contiguous; route points match stops; stops inside the service area; everything labelled DEMO / SIMULATED"],
  ["T-VIEW", "The status view gives LIVE / OFFLINE / NOT_IN_SERVICE / STALE for the four demo buses, the same answer as the package functions, and strict ISO timestamps"],
  ["E2E", "A real-clock update turns the STALE demo bus ACTIVE"],
], [1500, 8138], { firstColFill: true }));

p3.push(H2("7. Items to confirm with the team"));
p3.push(...tbl(["With", "Decision", "Current proposal"], [
  ["Wafiy", "Update interval and stale threshold", "5 s interval, STALE after 30 s, OFFLINE after 120 s"],
  ["Wafiy", "ETA source of truth and fallback speed", "Wafiy's function; 20 km/h fallback; ETA hidden unless ACTIVE. remaining_distance_m supplies the route distance"],
  ["Hazeem", "Older/duplicate handling and logging", "As in section 2 (done inside the database)"],
  ["Hazeem", "Database technology and architecture", "Oracle XE behind a backend API (Part 5)"],
  ["All", "Service-area box and max_jump_speed_kmh", "Demo values - adjust after the field survey"],
], [1500, 3700, 4438], { firstColFill: true }));

// =====================================================================
const p4 = [];
p4.push(H1("Part 4 - Oracle Setup, Reset and Access Guide", false));
p4.push(H2("1. What you need"));
p4.push(...tbl(["Item", "Requirement"], [
  ["Oracle Database", "Oracle Database Express Edition (XE) 21c - the one installed from the 'Get Started With Oracle Database 21c Express Edition' shortcut. 18c XE and 23ai Free also work. The setup program asks you to choose a password for the SYS and SYSTEM accounts: remember it."],
  ["A SQL tool", "**SQL Plus** (installed with XE; open it from the Start menu or run `sqlplus`) **or** Oracle SQL Developer (free download). Either is fine."],
  ["The project folder", "The folder that contains the oracle folder with the scripts. Open your SQL tool from inside the oracle folder, so that @install_all.sql finds the other scripts."],
  ["Python (optional)", "3.9 or newer, only for the reference tests (no packages) and the backend example (`pip install oracledb`)"],
], [2300, 7338], { firstColFill: true }));
p4.push(...box("In XE 21c your data lives in a pluggable database called **XEPDB1** (service name XEPDB1). The database itself is reached with service name XE. The users below are created **inside XEPDB1**; if you create them in the root container you get ORA-65096.", AMBER));

p4.push(H2("2. Build the demo database (about 1 minute)"));
p4.push(P("**Step 1 - create the users (once).** Start SQL*Plus and connect to the root as SYSTEM, using the password you chose at installation:"));
p4.push(...code([
  "sqlplus system@//localhost:1521/XE",
  "SQL> @00_create_users.sql",
  "SQL> EXIT",
]));
p4.push(P("The script switches to XEPDB1 and creates BUS_OWNER, BUS_APP and BUS_READONLY. **Before sharing the file or pushing it to GitHub, change the three passwords inside it** (they are placeholders)."));
p4.push(P("**Step 2 - install schema, package and demo data.** Connect as BUS_OWNER to XEPDB1, from the oracle folder:"));
p4.push(...code([
  "cd oracle",
  "sqlplus bus_owner@//localhost:1521/XEPDB1",
  "SQL> @install_all.sql",
]));
p4.push(P("Expected end of the output (ages matter, not the exact clock):"));
p4.push(...code([
  "BUS_ID   DISPLAY_STATUS  DATA_FRESHNESS  AGE_SECONDS",
  "BUS-01   ACTIVE          LIVE                      5",
  "BUS-02   OFFLINE         OFFLINE                 600",
  "BUS-03   NOT_IN_SERVICE  UNAVAILABLE",
  "BUS-04   STALE           STALE                    60",
]));
p4.push(P("What install_all.sql does: 01_schema.sql creates all tables, constraints, the trigger, indexes, views and column comments; 02_package.sql compiles pkg_bus_tracker; 03_seed.sql inserts the demo data and turns the demo ages into real UTC timestamps (now minus age); 04_grants.sql gives BUS_APP and BUS_READONLY their limited rights. If a script fails it stops (WHENEVER SQLERROR) and rolls back."));
p4.push(...box("**SQL Developer:** create a connection with user BUS_OWNER, host localhost, port 1521, **Service name XEPDB1**. Open each file (01, 02, 03, 04) and press **F5 (Run Script)**, in that order. Do not use the 'Run Statement' button (F9) for the package files."));

p4.push(H2("3. Reset / reseed (do this before every demo)"));
p4.push(P("The demo timestamps are relative to 'now', so a database loaded yesterday looks OFFLINE today. Re-time them right before a demo:"));
p4.push(...code(["SQL> EXEC pkg_bus_tracker.refresh_demo_locations;"]));
p4.push(P("Within about 30 s BUS-01 turns STALE and after 120 s OFFLINE; that is expected and is useful for demonstrating the freshness states. To keep a bus LIVE during a demo, send updates (section 6) or run the command again. For a **full reset** (everything dropped and rebuilt):"));
p4.push(...code(["SQL> @99_drop_all.sql", "SQL> @install_all.sql"]));
p4.push(P("99_drop_all.sql deletes every table, view and package in the BUS_OWNER schema, so only ever run it as BUS_OWNER."));

p4.push(H2("4. Verify everything works"));
p4.push(...code([
  "SQL> @05_tests.sql                       -- 117 database checks; ends with ALL TESTS PASSED",
  "python3 tests/test_data_quality.py       -- 62 reference checks, no Oracle needed",
]));
p4.push(P("Both must end with 0 failures. Run them after any change to the schema, the package, the seed or the rules. Write the result into the table in Part 1, section 1.7."));

p4.push(H2("5. Look at the data"));
p4.push(...code([
  "SELECT * FROM v_route_stops WHERE route_id = 'RTE-A' ORDER BY stop_sequence;",
  "SELECT bus_id, display_status, data_freshness, age_seconds, timestamp_iso FROM v_bus_status;",
  "SELECT * FROM location_log ORDER BY log_id;",
  "SELECT table_name, column_name, comments FROM user_col_comments WHERE table_name = 'BUS_LOCATIONS';",
]));

p4.push(H2("6. Try the update flow"));
p4.push(...code([
  "SET SERVEROUTPUT ON",
  "DECLARE",
  "  v_o VARCHAR2(30); v_r VARCHAR2(60);",
  "BEGIN",
  "  pkg_bus_tracker.apply_location_update(",
  "    p_bus_id => 'BUS-01', p_latitude => 4.3827, p_longitude => 100.9692,",
  "    p_timestamp => pkg_bus_tracker.to_iso_utc(SYS_EXTRACT_UTC(SYSTIMESTAMP)),",
  "    p_outcome => v_o, p_reason => v_r, p_data_source => 'SIMULATED');",
  "  DBMS_OUTPUT.PUT_LINE(v_o || ' / ' || v_r);",
  "END;",
  "/",
]));
p4.push(P("Prints ACCEPT / OK. Running it again within the same second prints IGNORE_DUPLICATE / DUPLICATE_TIMESTAMP, and SELECT * FROM location_log shows every outcome. Always use named parameters (=>) when calling the procedure."));

p4.push(H2("7. Replacing demo data with real data (after the field survey)"));
p4.push(B("Edit only the data block at the top of seed/build_seed.py (stop coordinates, names, routes, buses)."));
p4.push(B("Change dataOrigin from DEMO to SURVEYED (or OFFICIAL) **only for data that really is**."));
p4.push(B("Run `python3 seed/build_seed.py`, then `python3 seed/make_oracle_seed.py`, then `@99_drop_all.sql` and `@install_all.sql`, then the tests. (Test T-SEED10 insists that everything is DEMO; change that check when real data arrives.)"));
p4.push(B("Route distances are recalculated automatically. Replace route path points with traced road points for accurate distances; until then do not claim accurate distances or ETA."));
p4.push(B("Update the bbox_* values in system_config to match the real campus area."));
p4.push(P("Never describe simulated positions as real live service. Real driver/device locations need university and transport approval first (blueprint, section 12)."));

p4.push(H2("8. Safe copy of non-sensitive test data"));
p4.push(P("seed/seed.json is the safe, non-sensitive master copy of the demo data (no personal data, no real driver locations). Commit it to Git. Together with the scripts in oracle/ it is enough to rebuild the whole database on any laptop that has Oracle XE. Do not commit passwords, .env files, database dumps (.dmp) or location_log exports from real tests; the included .gitignore already excludes them."));

p4.push(H2("9. Access and permissions notes (agree with Hazeem)"));
p4.push(...tbl(["Who / what", "Reference data + views", "bus_locations", "location_log", "system_config"], [
  ["Student app (Keanu)", "No database login. Reads through the backend API", "Via backend", "No access", "Via backend"],
  ["GPS sender (Wafiy)", "No access", "**No direct write** - sends to the backend only", "No access", "No access"],
  ["Backend (Hazeem) as BUS_APP", "Read", "Read. Writes only by calling pkg_bus_tracker.apply_location_update", "Read (debugging); written by the package", "Read"],
  ["Read-only account BUS_READONLY", "Read", "Read", "No access", "Read"],
  ["Admin (optional, later)", "Read + write, authenticated, through the backend", "No", "Read", "Write"],
  ["Roy as BUS_OWNER", "Reseed / maintain", "Reseed only", "Trim", "Maintain"],
], [2100, 2300, 2400, 1700, 1138], { firstColFill: true }));
p4.push(B("The student app never receives database credentials and never writes directly."));
p4.push(B("BUS_APP has SELECT on tables and views and EXECUTE on the package, **nothing else**: it cannot insert, update or delete a table directly, so a bug in the backend cannot corrupt reference data."));
p4.push(B("No user names, emails or phone numbers are stored anywhere in the core schema. (The optional AlertPreferences table, if built later, must use an anonymous device ID only.)"));
p4.push(B("Keep passwords, .env files and database dumps out of Git. Give the backend its password through an environment variable."));

p4.push(H2("10. Troubleshooting"));
p4.push(...tbl(["Symptom", "Cause / fix"], [
  ["ORA-12541: no listener / ORA-12514: service not known", "The database is not running or the service name is wrong. Start the Windows services OracleServiceXE and the OracleOraDB21Home1TNSListener; use //localhost:1521/XEPDB1 (or /XE for SYSTEM)"],
  ["ORA-01017: invalid username/password", "Wrong password. For SYSTEM use the password chosen at installation; for BUS_OWNER the one in 00_create_users.sql"],
  ["ORA-28000: account is locked", "As SYSTEM: ALTER USER bus_owner ACCOUNT UNLOCK;"],
  ["ORA-65096: invalid common user or role name", "The user was created in the root container. Run ALTER SESSION SET CONTAINER = XEPDB1; first (00_create_users.sql does this)"],
  ["ORA-01950: no privileges on tablespace 'USERS'", "Quota missing: as SYSTEM, in XEPDB1: ALTER USER bus_owner QUOTA UNLIMITED ON users;"],
  ["ORA-01031: insufficient privileges on CREATE ...", "A GRANT in 00_create_users.sql was skipped. Run it again as SYSTEM"],
  ["SP2-0310: unable to open file '01_schema.sql'", "SQL*Plus was started in the wrong folder. cd into the oracle folder first"],
  ["ORA-00955: name is already used by an existing object", "The schema is already installed. Run 99_drop_all.sql first, or only refresh the demo data (section 3)"],
  ["ORA-00942: table or view does not exist (as BUS_APP)", "Use the owner's name: BUS_OWNER.v_bus_status, or run ALTER SESSION SET CURRENT_SCHEMA = BUS_OWNER; after connecting"],
  ["PLS-00201 / ORA-06550 compile errors in the package", "Run SHOW ERRORS right after the package script and read the first message; send it to Roy"],
  ["ORA-02290: check constraint (BUS_OWNER.CK_...) violated", "A value breaks a rule (for example an ID like STP-01!). The constraint name tells you which rule. Fix the data"],
  ["ORA-02291: integrity constraint violated - parent key not found", "A record points to something that does not exist (e.g. unknown stop in a route)"],
  ["ORA-20001: OLDER_OR_DUPLICATE_TIMESTAMP on a direct UPDATE", "The safety trigger working as designed; use apply_location_update or a newer timestamp"],
  ["Buses all show OFFLINE", "The demo data is old. Run EXEC pkg_bus_tracker.refresh_demo_locations;"],
  ["Updates are not accepted", "Check the timestamp format (...Z, UTC) and that it is newer than the stored one; look at location_log.reason_code"],
], [3700, 5938]));

p4.push(H2("11. Project files"));
p4.push(...tbl(["File", "Purpose"], [
  ["oracle/00_create_users.sql", "Creates BUS_OWNER, BUS_APP, BUS_READONLY in XEPDB1 (run once as SYSTEM)"],
  ["oracle/01_schema.sql", "Tables, constraints, trigger, indexes, views, column comments"],
  ["oracle/02_package.sql", "pkg_bus_tracker: validation, logging, freshness, ETA helper, route distance, demo refresh"],
  ["oracle/03_seed.sql", "Demo data (generated - do not edit by hand)"],
  ["oracle/04_grants.sql", "Least-privilege rights for BUS_APP and BUS_READONLY"],
  ["oracle/05_tests.sql", "117 database checks"],
  ["oracle/99_drop_all.sql, install_all.sql", "Full reset / one-command install"],
  ["seed/build_seed.py -> seed/seed.json", "Generates / holds the demo data (master copy)"],
  ["seed/make_oracle_seed.py", "seed.json -> oracle/03_seed.sql"],
  ["data_quality.py, tests/test_data_quality.py", "Executable specification of the rules (62 checks) and a port source for the backend"],
  ["examples/backend_oracle_example.py", "How the backend submits a location and reads bus status from Oracle"],
  ["scripts/make_erd.py, docs/erd.png / erd.svg", "Redraws the ERD from the schema"],
  ["seed/build_seed_v11.py, seed/seed_v11.json", "Archive of the v1.1 generator and data (for reference only)"],
], [3900, 5738]));

// =====================================================================
const p5 = [];
p5.push(H1("Part 5 - Technology Decision: Oracle and the Backend", false));
p5.push(H2("1. The decision"));
p5.push(P("The blueprint left the database open (Firebase Realtime Database or Firestore). The team has chosen **Oracle Database XE** because it is free and easy to access. This part records what that means for each module."));
p5.push(...tbl(["Decision", "Chosen", "Date", "Agreed by"], [
  ["Production database", "Oracle Database XE 21c", "October 2026", "Roy - **Hazeem to confirm**"],
  ["Access path for the app", "Flutter app -> HTTP -> backend API -> Oracle (no direct connection)", "", "Roy - **Hazeem, Keanu to confirm**"],
], [2300, 4300, 1400, 1638], { firstColFill: true }));

p5.push(H2("2. Architecture"));
p5.push(...code([
  "  GPS sender / simulator (Wafiy)",
  "          |  HTTP POST  /locations   (JSON payload, Part 2 section 6)",
  "          v",
  "  Backend API (Hazeem)  --- python-oracledb or node-oracledb --->  Oracle XE  (BUS_APP account)",
  "          ^                                                         pkg_bus_tracker.apply_location_update",
  "          |  HTTP GET  /buses  /routes  /stops                      views v_bus_status, v_route_stops",
  "          |",
  "  Flutter student app (Keanu)   -- polls every ~5 s, shows status and the last-update time",
]));
p5.push(H3("Why a backend is required"));
p5.push(B("Oracle speaks its own network protocol (SQL*Net), not HTTP. A Flutter app cannot use it directly, and it must never contain database credentials anyway (team plan, 3.5 and 4.6)."));
p5.push(B("The backend can be small: two or three endpoints that call the package and read the views. See examples/backend_oracle_example.py (Python)."));
p5.push(B("**Options for Hazeem:** (A) Python with FastAPI or Flask + python-oracledb (thin mode, no Oracle client install); (B) Node.js with node-oracledb; (C) Oracle REST Data Services (ORDS, free) can expose tables/views as REST with no code, but custom logic and validation are easier in A or B."));
p5.push(H3("What still works, and what is different from Firebase"));
p5.push(...tbl(["Topic", "With Oracle"], [
  ["Live updates to the app", "Polling every 5 s (the sender interval). No Firebase-style listeners; for a campus demo this is fine"],
  ["Push notifications (alerts)", "Firebase Cloud Messaging can still be used for push only. It does not need Firestore. Optional, phase 5"],
  ["Free tier limits", "None to watch: Oracle XE runs locally. XE limits (about 2 GB RAM, 2 CPU threads, 12 GB of user data - check Oracle's current XE page) are far above this project's needs (under 1 MB)"],
  ["Where the database runs", "On the laptop that hosts the backend. For a phone to reach the backend, both must be on the same Wi-Fi (use the laptop's IP address) and the firewall must allow the backend port. Keep a screenshot/video fallback for the demo"],
  ["Cloud alternative", "If the team needs a shared database without a laptop, Oracle Cloud's Always Free Autonomous Database exists (needs an Oracle Cloud account). The same scripts work; not needed for the prototype"],
  ["Security", "Backend connects as BUS_APP (read + EXECUTE only). Passwords in environment variables, never in Git or in the app"],
], [2600, 7038], { firstColFill: true }));

p5.push(H2("3. How the backend calls the database"));
p5.push(P("**Submit a location** - one call, and the database decides (11 checks, log, conditional write):"));
p5.push(...code([
  "outcome = cur.var(str); reason = cur.var(str)",
  "cur.execute(\"\"\"BEGIN pkg_bus_tracker.apply_location_update(",
  "      p_bus_id => :bus, p_latitude => :lat, p_longitude => :lng, p_timestamp => :ts,",
  "      p_outcome => :outcome, p_reason => :reason,",
  "      p_speed_kmh => :speed, p_accuracy_m => :acc, p_data_source => :src); END;\"\"\",",
  "  dict(bus=..., lat=..., lng=..., ts=..., outcome=outcome, reason=reason, speed=..., acc=..., src=...))",
  "return outcome.getvalue(), reason.getvalue()      # e.g. ('ACCEPT', 'OK')",
]));
p5.push(P("**Read the map data** - `SELECT ... FROM bus_owner.v_bus_status`. Suggested HTTP status codes: ACCEPT -> 200; IGNORE_DUPLICATE / IGNORE_OLDER -> 200 with the outcome in the body (the sender did nothing wrong); REJECT -> 400 with the reason code."));
p5.push(H3("Column -> JSON field mapping (v_bus_status)"));
p5.push(...tbl(["Oracle column", "JSON field", "Oracle column", "JSON field"], [
  ["bus_id", "busId", "speed_kmh", "speedKmh"],
  ["label", "label", "accuracy_m", "accuracyM"],
  ["route_id", "routeId", "data_source", "dataSource"],
  ["service_state", "serviceState", "age_seconds", "ageSeconds"],
  ["data_origin", "dataOrigin", "data_freshness", "dataFreshness"],
  ["latitude / longitude", "latitude / longitude", "display_status", "displayStatus"],
  ["**timestamp_iso**", "**timestamp**", "received_at_iso", "receivedAt"],
], [2400, 2400, 2400, 2438]));
p5.push(P("Routes for the app: join v_route_stops (ordered stops) and route_points (polyline). Remember the three renamed columns: stop_sequence -> sequence; config_key -> key; config_value -> value."));
p5.push(P("**Route-aware distance for ETA (Wafiy):** `SELECT pkg_bus_tracker.remaining_distance_m('RTE-A', :lat, :lng, 'STP-03') FROM dual` returns the metres still to travel along the route (NULL if unknown or already past a stop on a non-loop route). Then `pkg_bus_tracker.eta_minutes(distance, speed)`, using default_avg_speed_kmh when the live speed is missing. Wafiy remains the owner of the final ETA logic."));

p5.push(H2("4. Differences between SQLite (v1.1) and Oracle that were handled"));
p5.push(...tbl(["Topic", "SQLite (v1.1)", "Oracle (v1.2)"], [
  ["Text pattern checks", "GLOB '*[^0-9]*'", "REGEXP_LIKE(col, '^STP-[0-9]+$', 'c')"],
  ["Empty string", "'' is a value", "'' **is NULL** - blank-text checks rewritten as TRIM(x) IS NOT NULL"],
  ["CHECK returning NULL", "Fails", "**Passes** - every rule written so NULL cannot slip through (NOT NULL columns + explicit checks)"],
  ["Foreign keys", "Only with PRAGMA on every connection", "Always enforced; FK columns indexed"],
  ["Date/time", "TEXT + datetime()", "TIMESTAMP(0) in UTC + SYS_EXTRACT_UTC(SYSTIMESTAMP)"],
  ["Upsert", "INSERT ... ON CONFLICT DO UPDATE", "MERGE ... WHEN MATCHED ... WHERE ... WHEN NOT MATCHED"],
  ["Auto numbers", "AUTOINCREMENT", "GENERATED ALWAYS AS IDENTITY"],
  ["Trigger", "SELECT RAISE(ABORT, ...)", "RAISE_APPLICATION_ERROR(-20001, ...) with a WHEN (NEW... <= OLD...) clause"],
  ["Booleans", "0 / 1", "NUMBER(1) 0 / 1 (BOOLEAN type exists only from 23ai)"],
  ["Reserved words", "SEQUENCE, KEY, VALUE allowed", "Columns renamed: stop_sequence, config_key, config_value"],
  ["SQL scripts", "executescript", "SQL*Plus scripts: PL/SQL blocks end with / ; SET DEFINE OFF; SET SQLBLANKLINES ON"],
], [2200, 3400, 4038], { firstColFill: true }));

p5.push(H2("5. Next steps"));
p5.push(N("Roy: run the scripts on the team's Oracle XE, run 05_tests.sql, fill in the test record (Part 1, 1.7). Send any ORA- or PLS- error text if something fails.", "num2"));
p5.push(N("Roy + Hazeem: confirm the architecture in section 2 and the endpoint list; Hazeem tries examples/backend_oracle_example.py against the demo database.", "num2"));
p5.push(N("Keanu: confirm which fields each screen needs (Part 2) and use the camelCase JSON examples as test data.", "num2"));
p5.push(N("Wafiy: confirm thresholds (Part 1, 1.5) and test remaining_distance_m against real test drives once stops are surveyed.", "num2"));
p5.push(N("All: field survey of real stops and route points, then replace the demo data (Part 4, section 7).", "num2"));

// =====================================================================
const numbering = {
  config: [
    { reference: "bul", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 270 } } } },
                                  { level: 1, format: LevelFormat.BULLET, text: "\u2013", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 1000, hanging: 270 } } } }] },
    { reference: "num", levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 340 } } } }] },
    { reference: "num2", levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 340 } } } }] },
  ],
};
const footer = new Footer({ children: [new Paragraph({
  alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: "Smart Campus Bus Tracker | Database Documentation v1.2 (Oracle) | DEMO / SIMULATED DATA | Page ", font: FONT, size: 16, color: "78909C" }),
             new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 16, color: "78909C" })],
})] });

const A4 = { width: 11906, height: 16838 };
const margin = { top: 1134, bottom: 1134, left: 1134, right: 1134 };

// ERD section (landscape A4: content width 14570 DXA = 10.1 in)
const erdW = 14570, erdPx = 2720, erdPy = 1181;
const erdSection = [
  new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun({ text: "Entity Relationship Diagram", font: FONT })] }),
  P("Blue tables hold reference data, orange tables hold live and audit data, purple holds configuration, grey is a demo helper. A crow's foot marks the 'many' side of a relationship; a circle means optional. location_log has no foreign key on purpose, so that updates for unknown bus IDs can still be logged. Types are Oracle types; ? = may be NULL."),
  new Paragraph({ alignment: AlignmentType.CENTER, children: [new ImageRun({ type: "png", data: erd, transformation: { width: 940, height: Math.round(940 * erdPy / erdPx) },
    altText: { title: "ERD", description: "Entity relationship diagram of the Oracle schema", name: "erd" } })] }),
];

const doc = new Document({
  creator: "Roy - Person 3", title: "Smart Campus Bus Tracker - Database Documentation (Oracle v1.2)",
  styles: {
    default: { document: { run: { font: FONT, size: 21 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 34, bold: true, font: FONT, color: SLATE }, paragraph: { spacing: { before: 120, after: 160 }, outlineLevel: 0, border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: "90A4AE", space: 4 } } } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 26, bold: true, font: FONT, color: BLUE }, paragraph: { spacing: { before: 260, after: 100 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 22, bold: true, font: FONT, color: SLATE }, paragraph: { spacing: { before: 180, after: 80 }, outlineLevel: 2 } },
    ],
  },
  numbering,
  sections: [
    { properties: { page: { size: A4, margin } }, footers: { default: footer }, children: c },
    { properties: { page: { size: A4, margin: { top: 900, bottom: 900, left: 1134, right: 1134 } } }, footers: { default: footer }, children: [] },
  ].slice(0, 1).concat([
    { properties: { page: { size: { ...A4, orientation: PageOrientation.LANDSCAPE }, margin: { top: 900, bottom: 900, left: 1134, right: 1134 } } }, footers: { default: footer }, children: erdSection },
    { properties: { page: { size: A4, margin } }, footers: { default: footer }, children: [...p2, ...p3, ...p4, ...p5] },
  ]),
});

Packer.toBuffer(doc).then((buf) => { fs.writeFileSync(OUT, buf); console.log("wrote", OUT); });
