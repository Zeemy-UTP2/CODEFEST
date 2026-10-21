"""Draw the Oracle ERD (docs/erd.png + docs/erd.svg) with Graphviz.  Usage: python3 scripts/make_erd.py
Needs the Graphviz 'dot' program (only for redrawing the picture)."""
import pathlib, subprocess

OUT = pathlib.Path(__file__).resolve().parent.parent / "docs"
REF, LIVE, CFG, DEMO = "#E3F2FD", "#FFF0DE", "#F3E5F5", "#EEEEEE"

def table(name, color, rows, note=None):
    h = f'<TR><TD COLSPAN="2" BGCOLOR="#37474F"><FONT COLOR="white"><B>{name}</B></FONT></TD></TR>'
    body = ""
    for key, col, typ in rows:
        k = f"<B>{key}</B> " if key else ""
        body += f'<TR><TD ALIGN="LEFT">{k}{col}</TD><TD ALIGN="LEFT"><FONT COLOR="#546E7A">{typ}</FONT></TD></TR>'
    n = f'<TR><TD COLSPAN="2"><FONT POINT-SIZE="9" COLOR="#78909C"><I>{note}</I></FONT></TD></TR>' if note else ""
    return f'{name} [shape=plain, label=<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="4" BGCOLOR="{color}">{h}{body}{n}</TABLE>>];'

T = [
 table("bus_locations", LIVE, [("PK FK","bus_id","VARCHAR2(20)"),("","latitude","NUMBER(10,7)"),("","longitude","NUMBER(10,7)"),
      ("","location_timestamp","TIMESTAMP(0) UTC"),("","received_at","TIMESTAMP(0) UTC"),("","speed_kmh","NUMBER(6,2) ?"),
      ("","accuracy_m","NUMBER(8,2) ?"),("","data_source","VARCHAR2(10)")], "trigger: no older overwrite"),
 table("location_log", LIVE, [("PK","log_id","NUMBER identity"),("","bus_id","VARCHAR2(40) ?"),("","latitude","NUMBER ?"),("","longitude","NUMBER ?"),
      ("","location_timestamp","VARCHAR2(40) ?"),("","received_at","TIMESTAMP(0)"),("","data_source","VARCHAR2(30) ?"),
      ("","outcome","VARCHAR2(20)"),("","reason_code","VARCHAR2(40)")], "no FK on purpose: unknown bus IDs are logged too"),
 table("system_config", CFG, [("PK","config_key","VARCHAR2(40)"),("","config_value","NUMBER"),("","unit","VARCHAR2(20)"),("","description","VARCHAR2(200)")], "thresholds read by all modules"),
 table("buses", REF, [("PK","bus_id","VARCHAR2(20)"),("","label","VARCHAR2(100)"),("FK","route_id","VARCHAR2(20) ?"),("","service_state","VARCHAR2(20)"),("","data_origin","VARCHAR2(10)")]),
 table("route_points", REF, [("PK FK","route_id","VARCHAR2(20)"),("PK","point_seq","NUMBER(5)"),("","latitude","NUMBER(10,7)"),("","longitude","NUMBER(10,7)"),
      ("FK","stop_id","VARCHAR2(20) ?"),("","cumulative_distance_m","NUMBER(9)  (new v1.2)")]),
 table("routes", REF, [("PK","route_id","VARCHAR2(20)"),("","name","VARCHAR2(100)"),("","description","VARCHAR2(300) ?"),("","colour_hex","VARCHAR2(7)"),
      ("","is_loop","NUMBER(1)"),("","total_length_m","NUMBER(9)"),("","active","NUMBER(1)"),("","data_origin","VARCHAR2(10)")]),
 table("stops", REF, [("PK","stop_id","VARCHAR2(20)"),("","name","VARCHAR2(100)"),("","latitude","NUMBER(10,7)"),("","longitude","NUMBER(10,7)"),("","active","NUMBER(1)"),("","data_origin","VARCHAR2(10)")]),
 table("route_stops", REF, [("PK FK","route_id","VARCHAR2(20)"),("PK","stop_sequence","NUMBER(4)"),("FK","stop_id","VARCHAR2(20)"),
      ("","cumulative_distance_m","NUMBER(9)"),("","distance_to_next_m","NUMBER(9) ?")], "UNIQUE (route_id, stop_id)"),
 table("demo_location_template", DEMO, [("PK FK","bus_id","VARCHAR2(20)"),("","latitude / longitude","NUMBER(10,7)"),("","age_seconds","NUMBER(8)"),
      ("","speed_kmh, accuracy_m","NUMBER ?"),("","data_source","VARCHAR2(10)")], "demo only: re-timed by refresh_demo_locations"),
]
E = lambda a, b, lab, tail, head="tee": f'{a} -> {b} [dir=both, arrowtail={tail}, arrowhead={head}, label="  {lab}", fontsize=10, color="#455A64", fontcolor="#455A64"];'
edges = [
 E("bus_locations","buses","bus_id","teeodot"),
 E("buses","routes","route_id","crowodot"),
 E("route_points","routes","route_id","crow"),
 E("route_points","stops","stop_id","crowodot"),
 E("route_stops","routes","route_id","crow"),
 E("route_stops","stops","stop_id","crow"),
 E("demo_location_template","buses","bus_id","teeodot"),
]
dot = f'''digraph ERD {{
  graph [rankdir=TB, nodesep=0.7, ranksep=0.9, fontname="Helvetica", labelloc=t, fontsize=20,
         label=<<B>Smart Campus Bus Tracker - Entity Relationship Diagram (Oracle v1.2)</B><BR/><FONT POINT-SIZE="13">Blue = reference data   Orange = live / audit data   Purple = configuration   Grey = demo helper</FONT>>];
  node [fontname="Helvetica", fontsize=12];
  edge [fontname="Helvetica"];
  {chr(10).join(T)}
  {chr(10).join(edges)}
  {{rank=same; location_log; bus_locations; system_config}}
  {{rank=same; buses; route_points; demo_location_template}}
  {{rank=same; routes; stops}}
}}'''
(OUT/"erd.dot").write_text(dot)
for fmt, extra in (("png", ["-Gdpi=110"]), ("svg", [])):
    subprocess.run(["dot", f"-T{fmt}", *extra, str(OUT/"erd.dot"), "-o", str(OUT/f"erd.{fmt}")], check=True)
print("wrote", OUT/"erd.png", "and erd.svg")
