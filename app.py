"""
GADMS Analytics Dashboard  +  Admin Backend
=============================================
DSCD 606 Data Management Techniques  |  University of Ghana

Two connection modes (auto-detected):
  1. Cloud Postgres  -- if DATABASE_URL is in st.secrets or env vars
  2. Local DuckDB    -- loads ./TEAM_ALPHA.sql into an in-memory DB (read-only demo)

Admin panel writes directly to Postgres (Supabase/Render/etc.) so every
addition is immediately reflected in the dashboard without a page reload.
"""

import os
import re
from datetime import date
from pathlib import Path

import pandas as pd
import streamlit as st
import plotly.express as px

# =====================================================================
# PAGE CONFIG
# =====================================================================
st.set_page_config(
    page_title="GADMS Analytics",
    page_icon="🎓",
    layout="wide",
    initial_sidebar_state="expanded",
)

st.markdown("""
<style>
  .block-container { padding-top: 2rem; padding-bottom: 2rem; }
  [data-testid="stMetricValue"] { font-size: 2rem; font-weight: 700; color: #1F3864; }
  [data-testid="stMetricLabel"] { font-size: 0.9rem; color: #555; }
  h1 { color: #1F3864; }
  h2, h3 { color: #2E75B6; }
  .stTabs [data-baseweb="tab-list"] { gap: 8px; }
  .stTabs [data-baseweb="tab"] {
      background-color: #F2F6FB; border-radius: 6px 6px 0 0; padding: 8px 16px;
  }
  .stTabs [aria-selected="true"] { background-color: #1F3864 !important; color: white !important; }
  .admin-box { background: #F2F6FB; border-radius: 10px; padding: 1.2rem; margin-bottom: 1rem; }
  .success-banner { background: #d4edda; color: #155724; border-radius: 8px;
                    padding: 0.8rem 1rem; font-weight: 600; margin-top: 0.5rem; }
  .warning-banner { background: #fff3cd; color: #856404; border-radius: 8px;
                    padding: 0.8rem 1rem; margin-top: 0.5rem; }
</style>
""", unsafe_allow_html=True)


# =====================================================================
# DATABASE CONNECTION
# =====================================================================
SQL_FILE = Path(__file__).parent / "TEAM_ALPHA.sql"


def _get_pg_url():
    try:
        url = st.secrets.get("DATABASE_URL")
        if url:
            return url
    except Exception:
        pass
    return os.environ.get("DATABASE_URL")


@st.cache_resource(show_spinner="Connecting to database…")
def get_connection():
    """Return (kind, connection-object). Postgres if available, else DuckDB."""
    pg_url = _get_pg_url()
    if pg_url:
        from sqlalchemy import create_engine
        engine = create_engine(pg_url, pool_pre_ping=True, pool_size=5, max_overflow=10)
        return "postgres", engine

    import duckdb
    con = duckdb.connect(":memory:")
    _load_sql_into_duckdb(con, SQL_FILE)
    return "duckdb", con


def _load_sql_into_duckdb(con, sql_path: Path):
    if not sql_path.exists():
        st.error(f"SQL file not found: {sql_path}")
        st.stop()
    raw = sql_path.read_text()
    t = raw.replace("SET client_min_messages = WARNING;", "")
    t = re.sub(r"SELECT setval\([^;]*\);", "", t)
    t = t.replace("BIGSERIAL", "BIGINT").replace("SERIAL", "INTEGER")
    buff, stmts = [], []
    for line in t.split("\n"):
        buff.append(line)
        if line.strip().endswith(";"):
            stmts.append("\n".join(buff))
            buff = []
    c = {"e": 0, "a": 0, "f": 0, "l": 0}
    for st_ in stmts:
        s = st_
        lines = s.split("\n")
        while lines and (lines[0].strip().startswith("--") or not lines[0].strip()):
            lines.pop(0)
        s = "\n".join(lines).strip()
        if not s:
            continue
        if s.startswith("INSERT INTO Enrollment "):
            c["e"] += 1
            s = s.replace("(StudentID,", "(EnrollmentID, StudentID,")
            s = s.replace(") VALUES (", f") VALUES ({c['e']}, ", 1)
        elif s.startswith("INSERT INTO AssessmentResult "):
            c["a"] += 1
            s = s.replace("(EnrollmentID,", "(ResultID, EnrollmentID,")
            s = s.replace(") VALUES (", f") VALUES ({c['a']}, ", 1)
        elif s.startswith("INSERT INTO FeePayment "):
            c["f"] += 1
            s = s.replace("(StudentID,", "(PaymentID, StudentID,")
            s = s.replace(") VALUES (", f") VALUES ({c['f']}, ", 1)
        elif s.startswith("INSERT INTO LMSActivity "):
            c["l"] += 1
            s = s.replace("(StudentID,", "(ActivityID, StudentID,")
            s = s.replace(") VALUES (", f") VALUES ({c['l']}, ", 1)
        try:
            con.execute(s)
        except Exception:
            pass


@st.cache_data(ttl=30, show_spinner=False)   # 30-second TTL — near real-time refresh
def q(sql: str) -> pd.DataFrame:
    kind, conn = get_connection()
    if kind == "postgres":
        return pd.read_sql_query(sql, conn)
    return conn.execute(sql).fetchdf()


def run_write(sql: str, params: tuple = ()):
    """Execute an INSERT/UPDATE/DELETE on Postgres. Returns (ok, error_msg)."""
    kind, conn = get_connection()
    if kind != "postgres":
        return False, "Admin writes require a live PostgreSQL connection. See setup instructions below."
    try:
        with conn.connect() as cx:
            from sqlalchemy import text
            cx.execute(text(sql), params)
            cx.commit()
        # Bust the read cache so charts refresh immediately
        q.clear()
        return True, None
    except Exception as ex:
        return False, str(ex)


# =====================================================================
# HEADER
# =====================================================================
col_l, col_r = st.columns([4, 1])
with col_l:
    st.title("🎓 GADMS Analytics Dashboard")
    st.caption(
        "Governed Academic Data Management System  •  "
        "DSCD 606 Data Management Techniques  •  University of Ghana"
    )
with col_r:
    kind, _ = get_connection()
    if kind == "postgres":
        badge = "🟢 Postgres (live)"
        badge_color = "#1F7864"
    else:
        badge = "🦆 DuckDB (read-only demo)"
        badge_color = "#856404"
    st.markdown(
        f"<div style='text-align:right; padding-top:1.2rem;'>"
        f"<span style='background:{badge_color};color:white;padding:6px 12px;"
        f"border-radius:6px;font-size:0.85rem;'>{badge}</span></div>",
        unsafe_allow_html=True,
    )

st.divider()

# =====================================================================
# SIDEBAR — global filters
# =====================================================================
st.sidebar.header("🔎 Filters")

programmes = q("SELECT DISTINCT ProgrammeName FROM Programme ORDER BY ProgrammeName")["ProgrammeName"].tolist()
sel_programmes = st.sidebar.multiselect("Programme", programmes, default=programmes)

statuses = q("SELECT DISTINCT Status FROM Student ORDER BY Status")["Status"].tolist()
sel_statuses = st.sidebar.multiselect("Student status", statuses, default=statuses)

genders = q("SELECT DISTINCT Gender FROM Student WHERE Gender IS NOT NULL ORDER BY Gender")["Gender"].tolist()
sel_genders = st.sidebar.multiselect("Gender", genders, default=genders)

st.sidebar.divider()
st.sidebar.markdown(
    "**About**  \n"
    "GADMS PostgreSQL schema: 12 tables, fully constrained with referential integrity.  \n\n"
    "**Tech**  \n"
    "Streamlit · Plotly · pandas · PostgreSQL / DuckDB"
)


def _in_clause(values):
    if not values:
        return "('__none__')"
    escaped = ",".join("'" + v.replace("'", "''") + "'" for v in values)
    return f"({escaped})"


P_FILTER = _in_clause(sel_programmes)
S_FILTER = _in_clause(sel_statuses)
G_FILTER = _in_clause(sel_genders)

STUDENT_WHERE = f"""
  s.Status   IN {S_FILTER}
  AND s.Gender IN {G_FILTER}
  AND p.ProgrammeName IN {P_FILTER}
"""

# =====================================================================
# KPI ROW
# =====================================================================
kpi_sql = f"""
SELECT
  (SELECT COUNT(*) FROM Student s JOIN Programme p ON s.ProgrammeID=p.ProgrammeID
   WHERE {STUDENT_WHERE}) AS students,
  (SELECT COUNT(*) FROM Enrollment e
   JOIN Student s ON s.StudentID=e.StudentID
   JOIN Programme p ON p.ProgrammeID=s.ProgrammeID
   WHERE {STUDENT_WHERE}) AS enrollments,
  (SELECT COUNT(*) FROM AssessmentResult) AS results,
  (SELECT ROUND(AVG(0.4*CourseworkScore + 0.6*ExamScore)::numeric, 2)
     FROM AssessmentResult) AS avg_mark,
  (SELECT COALESCE(SUM(Balance),0) FROM FeePayment) AS outstanding,
  (SELECT COUNT(*) FROM LMSActivity) AS lms_events
"""
if get_connection()[0] == "duckdb":
    kpi_sql = kpi_sql.replace("::numeric", "::DOUBLE")

kpi = q(kpi_sql).iloc[0]

c1, c2, c3, c4, c5, c6 = st.columns(6)
c1.metric("👥 Students", f"{int(kpi['students']):,}")
c2.metric("📚 Enrollments", f"{int(kpi['enrollments']):,}")
c3.metric("📝 Graded results", f"{int(kpi['results']):,}")
c4.metric("📊 Avg weighted mark", f"{float(kpi['avg_mark']):.2f}")
c5.metric("💰 Outstanding (GHS)", f"{float(kpi['outstanding']):,.0f}")
c6.metric("💻 LMS events", f"{int(kpi['lms_events']):,}")

st.divider()

# =====================================================================
# TABS  (analytics + admin)
# =====================================================================
tab_o, tab_p, tab_l, tab_f, tab_d, tab_q, tab_admin = st.tabs([
    "📊 Overview", "🎯 Performance", "💻 LMS Engagement",
    "💰 Finance", "🗂️ Data Explorer", "🧪 Query Lab", "⚙️ Admin"
])


# ---------- OVERVIEW ----------
with tab_o:
    st.subheader("Programme & demographic mix")
    a, b = st.columns(2)
    with a:
        df = q(f"""
            SELECT p.ProgrammeName, COUNT(*) AS Students
            FROM Student s JOIN Programme p ON s.ProgrammeID = p.ProgrammeID
            WHERE {STUDENT_WHERE}
            GROUP BY p.ProgrammeName ORDER BY Students DESC
        """)
        fig = px.bar(df, x="ProgrammeName", y="Students", text="Students",
                     color="Students", color_continuous_scale="Blues",
                     title="Students per programme")
        fig.update_traces(textposition="outside")
        fig.update_layout(showlegend=False, coloraxis_showscale=False,
                          xaxis_title="", yaxis_title="Students")
        st.plotly_chart(fig, use_container_width=True)
    with b:
        df = q(f"""
            SELECT s.Gender, COUNT(*) AS Students
            FROM Student s JOIN Programme p ON s.ProgrammeID = p.ProgrammeID
            WHERE {STUDENT_WHERE}
            GROUP BY s.Gender ORDER BY Students DESC
        """)
        fig = px.pie(df, names="Gender", values="Students", hole=0.5,
                     color_discrete_sequence=["#1F3864", "#2E75B6", "#8FAADC"],
                     title="Gender split")
        st.plotly_chart(fig, use_container_width=True)

    c, d = st.columns(2)
    with c:
        df = q(f"""
            SELECT s.Status, COUNT(*) AS Students
            FROM Student s JOIN Programme p ON s.ProgrammeID = p.ProgrammeID
            WHERE {STUDENT_WHERE}
            GROUP BY s.Status ORDER BY Students DESC
        """)
        fig = px.bar(df, x="Status", y="Students", text="Students",
                     color="Status", title="Status distribution",
                     color_discrete_sequence=px.colors.qualitative.Set2)
        fig.update_traces(textposition="outside")
        fig.update_layout(showlegend=False, xaxis_title="", yaxis_title="Students")
        st.plotly_chart(fig, use_container_width=True)
    with d:
        df = q(f"""
            SELECT p.ProgrammeName, s.Gender, COUNT(*) AS n
            FROM Student s JOIN Programme p ON s.ProgrammeID = p.ProgrammeID
            WHERE {STUDENT_WHERE}
            GROUP BY p.ProgrammeName, s.Gender
        """)
        fig = px.bar(df, x="ProgrammeName", y="n", color="Gender", barmode="stack",
                     title="Programme × Gender",
                     color_discrete_sequence=["#1F3864", "#2E75B6", "#8FAADC"])
        fig.update_layout(xaxis_title="", yaxis_title="Students")
        st.plotly_chart(fig, use_container_width=True)


# ---------- PERFORMANCE ----------
with tab_p:
    st.subheader("Academic performance")
    a, b = st.columns([2, 1])
    with a:
        cast = "DOUBLE" if get_connection()[0] == "duckdb" else "numeric"
        df = q(f"""
            SELECT p.ProgrammeName,
                   ROUND(AVG(0.4*ar.CourseworkScore + 0.6*ar.ExamScore)::{cast}, 2) AS AvgMark,
                   COUNT(*) AS Results
            FROM Programme p
            JOIN Student s        ON p.ProgrammeID = s.ProgrammeID
            JOIN Enrollment e     ON s.StudentID   = e.StudentID
            JOIN AssessmentResult ar ON ar.EnrollmentID = e.EnrollmentID
            WHERE {STUDENT_WHERE}
            GROUP BY p.ProgrammeName ORDER BY AvgMark DESC
        """)
        fig = px.bar(df, x="ProgrammeName", y="AvgMark", text="AvgMark",
                     color="AvgMark", color_continuous_scale="Tealgrn",
                     title="Average weighted mark by programme (40% CW + 60% Exam)")
        fig.update_traces(textposition="outside")
        fig.update_layout(yaxis_title="Avg mark", xaxis_title="",
                          coloraxis_showscale=False, yaxis_range=[0, 100])
        st.plotly_chart(fig, use_container_width=True)
    with b:
        df = q("""
            SELECT FinalGrade AS Grade, COUNT(*) AS Count
            FROM AssessmentResult GROUP BY FinalGrade
            ORDER BY CASE FinalGrade
                WHEN 'A' THEN 1 WHEN 'B+' THEN 2 WHEN 'B' THEN 3
                WHEN 'C+' THEN 4 WHEN 'C' THEN 5 WHEN 'D+' THEN 6
                WHEN 'D' THEN 7 WHEN 'F' THEN 8 ELSE 9 END
        """)
        fig = px.bar(df, x="Grade", y="Count", text="Count",
                     color="Grade", title="Grade distribution",
                     color_discrete_sequence=px.colors.qualitative.Bold)
        fig.update_traces(textposition="outside")
        fig.update_layout(showlegend=False, xaxis_title="", yaxis_title="Count")
        st.plotly_chart(fig, use_container_width=True)

    st.markdown("##### Coursework vs Exam — each dot is one assessment result")
    df = q(f"""
        SELECT ar.CourseworkScore, ar.ExamScore, ar.FinalGrade, p.ProgrammeName
        FROM AssessmentResult ar
        JOIN Enrollment e ON e.EnrollmentID = ar.EnrollmentID
        JOIN Student s    ON s.StudentID = e.StudentID
        JOIN Programme p  ON p.ProgrammeID = s.ProgrammeID
        WHERE {STUDENT_WHERE}
    """)
    fig = px.scatter(df, x="CourseworkScore", y="ExamScore", color="FinalGrade",
                     symbol="ProgrammeName", opacity=0.75,
                     color_discrete_sequence=px.colors.qualitative.Bold)
    fig.add_shape(type="line", x0=0, y0=50, x1=100, y1=50, line=dict(color="grey", dash="dot"))
    fig.add_shape(type="line", x0=50, y0=0, x1=50, y1=100, line=dict(color="grey", dash="dot"))
    fig.update_layout(xaxis_title="Coursework score", yaxis_title="Exam score",
                      xaxis_range=[0, 100], yaxis_range=[0, 100])
    st.plotly_chart(fig, use_container_width=True)


# ---------- LMS ----------
with tab_l:
    st.subheader("LMS engagement vs outcome — early-warning view")
    df = q(f"""
        SELECT s.StudentID,
               s.FirstName || ' ' || s.LastName AS FullName,
               p.ProgrammeName,
               co.CourseOfferingID,
               COUNT(l.ActivityID) AS Events,
               COALESCE(SUM(l.DurationMinutes),0) AS Minutes,
               ar.FinalGrade
        FROM Student s
        JOIN Programme p       ON p.ProgrammeID = s.ProgrammeID
        JOIN Enrollment e      ON e.StudentID = s.StudentID
        JOIN CourseOffering co ON co.CourseOfferingID = e.CourseOfferingID
        LEFT JOIN LMSActivity l ON l.StudentID = s.StudentID
                               AND l.CourseOfferingID = co.CourseOfferingID
        LEFT JOIN AssessmentResult ar ON ar.EnrollmentID = e.EnrollmentID
        WHERE {STUDENT_WHERE}
        GROUP BY s.StudentID, s.FirstName, s.LastName, p.ProgrammeName,
                 co.CourseOfferingID, ar.FinalGrade
    """)
    a, b = st.columns(2)
    with a:
        fig = px.scatter(df, x="Minutes", y="Events", color="FinalGrade", size_max=14,
                         hover_data=["FullName", "ProgrammeName", "CourseOfferingID"],
                         color_discrete_sequence=px.colors.qualitative.Bold,
                         title="LMS minutes vs LMS events  (colour = final grade)")
        fig.update_layout(xaxis_title="Total minutes", yaxis_title="LMS events")
        st.plotly_chart(fig, use_container_width=True)
    with b:
        atype = q("""SELECT ActivityType, COUNT(*) AS n
                     FROM LMSActivity GROUP BY ActivityType ORDER BY n DESC""")
        fig = px.bar(atype, x="ActivityType", y="n", text="n",
                     color="n", color_continuous_scale="Purples",
                     title="Activity-type breakdown")
        fig.update_traces(textposition="outside")
        fig.update_layout(showlegend=False, coloraxis_showscale=False,
                          xaxis_title="", yaxis_title="Events")
        st.plotly_chart(fig, use_container_width=True)

    st.markdown("##### Top 15 by LMS minutes")
    st.dataframe(df.sort_values("Minutes", ascending=False).head(15).reset_index(drop=True),
                 use_container_width=True, hide_index=True)


# ---------- FINANCE ----------
with tab_f:
    st.subheader("Fee governance")
    a, b = st.columns(2)
    with a:
        df = q("""SELECT PaymentMethod, COUNT(*) AS Payments, SUM(AmountPaid) AS Total
                  FROM FeePayment GROUP BY PaymentMethod ORDER BY Total DESC""")
        fig = px.bar(df, x="PaymentMethod", y="Total", text="Payments",
                     color="Total", color_continuous_scale="Greens",
                     title="Payment volume by method (bar=GHS, label=#tx)")
        fig.update_traces(textposition="outside")
        fig.update_layout(coloraxis_showscale=False, xaxis_title="", yaxis_title="Total (GHS)")
        st.plotly_chart(fig, use_container_width=True)
    with b:
        out = q(f"""
            SELECT s.StudentID, s.FirstName || ' ' || s.LastName AS FullName,
                   p.ProgrammeName, SUM(f.AmountPaid) AS Paid, SUM(f.Balance) AS Outstanding
            FROM Student s
            JOIN Programme p  ON p.ProgrammeID = s.ProgrammeID
            JOIN FeePayment f ON f.StudentID   = s.StudentID
            WHERE {STUDENT_WHERE}
            GROUP BY s.StudentID, s.FirstName, s.LastName, p.ProgrammeName
            HAVING SUM(f.Balance) > 0
            ORDER BY Outstanding DESC
        """)
        st.markdown("##### Students with outstanding balances")
        st.dataframe(out, use_container_width=True, hide_index=True,
                     column_config={
                         "Paid": st.column_config.NumberColumn(format="GHS %.2f"),
                         "Outstanding": st.column_config.NumberColumn(format="GHS %.2f"),
                     })


# ---------- DATA EXPLORER ----------
with tab_d:
    st.subheader("Browse any table")
    tables = ["Department", "Programme", "Course", "Lecturer", "Semester",
              "CourseOffering", "Student", "Enrollment", "AssessmentResult",
              "FeePayment", "LMSActivity"]
    pick = st.selectbox("Table", tables, index=tables.index("Student"))
    df = q(f"SELECT * FROM {pick}")
    st.caption(f"{len(df):,} rows  ·  {len(df.columns)} columns")
    st.dataframe(df, use_container_width=True, hide_index=True)
    st.download_button(f"⬇️ Download {pick}.csv", df.to_csv(index=False).encode(),
                       file_name=f"{pick}.csv", mime="text/csv")


# ---------- QUERY LAB ----------
with tab_q:
    st.subheader("Run your own SQL")
    st.caption("Read-only. Backed by your live GADMS database.")
    default_query = """SELECT p.ProgrammeName,
       ROUND(AVG(0.4*ar.CourseworkScore + 0.6*ar.ExamScore), 2) AS AvgMark,
       COUNT(*) AS Results
FROM Programme p
JOIN Student s        ON p.ProgrammeID = s.ProgrammeID
JOIN Enrollment e     ON s.StudentID   = e.StudentID
JOIN AssessmentResult ar ON ar.EnrollmentID = e.EnrollmentID
GROUP BY p.ProgrammeName
ORDER BY AvgMark DESC;"""
    sql_input = st.text_area("SQL", value=default_query, height=180)
    if st.button("▶ Run", type="primary"):
        sql = sql_input.strip().rstrip(";")
        forbidden = ("INSERT", "UPDATE", "DELETE", "DROP", "ALTER",
                     "TRUNCATE", "CREATE", "GRANT", "REVOKE")
        if any(w in sql.upper().split() for w in forbidden):
            st.error("Only read-only SELECT queries are allowed.")
        else:
            try:
                df = q(sql)
                st.success(f"Returned {len(df):,} rows.")
                st.dataframe(df, use_container_width=True, hide_index=True)
            except Exception as ex:
                st.error(f"Query failed: {ex}")


# =====================================================================
# ADMIN TAB
# =====================================================================
with tab_admin:
    st.subheader("⚙️ Admin — Data Entry Backend")

    is_live = get_connection()[0] == "postgres"

    if not is_live:
        st.warning(
            "**Admin writes require a live PostgreSQL connection.**  \n"
            "The app is currently running on embedded DuckDB (read-only demo mode).  \n\n"
            "**To enable admin writes:** add your `DATABASE_URL` to Streamlit Cloud secrets "
            "under *Settings → Secrets*.  See the README for the full setup guide."
        )
        st.info(
            "**Quick setup reminder:**\n"
            "1. Create a free Supabase project at https://supabase.com\n"
            "2. Paste `TEAM_ALPHA.sql` into the Supabase SQL Editor and run it\n"
            "3. Copy your connection URI from *Project Settings → Database → URI*\n"
            "4. In Streamlit Cloud → your app → *Settings → Secrets*, add:\n"
            "```\nDATABASE_URL = \"postgresql://postgres:PASSWORD@db.xxx.supabase.co:5432/postgres\"\n```\n"
            "5. Reboot the app — the badge turns green and admin writes are live"
        )
        st.stop()

    # ---- Admin password gate ----
    ADMIN_PASSWORD = st.secrets.get("ADMIN_PASSWORD", "gadms2026")
    if "admin_authenticated" not in st.session_state:
        st.session_state.admin_authenticated = False

    if not st.session_state.admin_authenticated:
        st.markdown("### 🔐 Admin Login")
        pwd = st.text_input("Password", type="password", placeholder="Enter admin password")
        if st.button("Login", type="primary"):
            if pwd == ADMIN_PASSWORD:
                st.session_state.admin_authenticated = True
                st.rerun()
            else:
                st.error("Incorrect password.")
        st.caption("Default password: `gadms2026`  — change via `ADMIN_PASSWORD` in Streamlit secrets.")
        st.stop()

    # ---- Authenticated admin UI ----
    st.success("✅ Logged in as Administrator")
    if st.button("🔓 Logout"):
        st.session_state.admin_authenticated = False
        st.rerun()

    st.divider()

    # Fetch reference data for dropdowns
    prog_df = q("SELECT ProgrammeID, ProgrammeName, DegreeType FROM Programme ORDER BY ProgrammeName")
    prog_options = {row["ProgrammeName"]: row["ProgrammeID"] for _, row in prog_df.iterrows()}

    offering_df = q("""
        SELECT co.CourseOfferingID,
               c.CourseCode || ' – ' || c.CourseTitle || ' (' || co.AcademicYear || ')' AS label
        FROM CourseOffering co
        JOIN Course c ON c.CourseID = co.CourseID
        ORDER BY co.CourseOfferingID
    """)
    offering_options = {row["label"]: row["courseofferingid"]
                        for _, row in offering_df.iterrows()}

    admin_tabs = st.tabs([
        "👤 Add Student",
        "📋 Enroll Student",
        "📝 Record Assessment",
        "💵 Record Payment",
        "📚 Add Course Offering",
        "🗑️ Manage Records",
    ])

    # ------------------------------------------------------------------
    # TAB 1 — ADD STUDENT
    # ------------------------------------------------------------------
    with admin_tabs[0]:
        st.markdown("#### Register a New Student")
        st.caption("All fields marked \\* are required. Changes reflect on the dashboard immediately.")

        with st.form("form_add_student", clear_on_submit=True):
            col1, col2 = st.columns(2)
            with col1:
                sid = st.text_input("Student ID *", placeholder="e.g. UG2026101",
                                    help="Must be unique – max 15 characters")
                fname = st.text_input("First Name *")
                lname = st.text_input("Last Name *")
                gender = st.selectbox("Gender *", ["Male", "Female", "Other"])
            with col2:
                prog_name = st.selectbox("Programme *", list(prog_options.keys()))
                dob = st.date_input("Date of Birth", value=date(2000, 1, 1),
                                    min_value=date(1950, 1, 1), max_value=date.today())
                email = st.text_input("Email *", placeholder="student@ug.edu.gh")
                phone = st.text_input("Phone Number", placeholder="+233 XX XXX XXXX")

            col3, col4 = st.columns(2)
            with col3:
                admission_year = st.number_input("Admission Year *", min_value=2000,
                                                  max_value=2100, value=2026)
            with col4:
                status = st.selectbox("Status *", ["Active", "Suspended", "Graduated", "Withdrawn"])

            submitted = st.form_submit_button("➕ Register Student", type="primary",
                                               use_container_width=True)

        if submitted:
            errors = []
            if not sid.strip():         errors.append("Student ID is required.")
            if len(sid.strip()) > 15:   errors.append("Student ID must be ≤ 15 characters.")
            if not fname.strip():        errors.append("First Name is required.")
            if not lname.strip():        errors.append("Last Name is required.")
            if not email.strip():        errors.append("Email is required.")
            if "@" not in email:         errors.append("Email looks invalid.")

            if errors:
                for e in errors:
                    st.error(e)
            else:
                pid = prog_options[prog_name]
                ok, err = run_write(
                    """INSERT INTO Student
                       (StudentID, ProgrammeID, FirstName, LastName, Gender,
                        DateOfBirth, Email, PhoneNumber, AdmissionYear, Status)
                       VALUES (:1,:2,:3,:4,:5,:6,:7,:8,:9,:10)""",
                    (sid.strip(), pid, fname.strip(), lname.strip(), gender,
                     dob, email.strip(), phone.strip() or None, int(admission_year), status)
                )
                if ok:
                    st.success(f"✅ Student **{fname} {lname}** ({sid}) registered successfully! "
                               f"The dashboard KPIs and charts have been updated.")
                    st.balloons()
                else:
                    if "unique" in err.lower() or "duplicate" in err.lower():
                        st.error(f"❌ A student with ID **{sid}** or email **{email}** already exists.")
                    else:
                        st.error(f"❌ Database error: {err}")

        st.divider()
        st.markdown("##### Currently Registered Students")
        stu_preview = q("""
            SELECT s.StudentID, s.FirstName, s.LastName, s.Gender,
                   p.ProgrammeName, s.Status, s.AdmissionYear, s.Email
            FROM Student s JOIN Programme p ON s.ProgrammeID = p.ProgrammeID
            ORDER BY s.StudentID DESC LIMIT 20
        """)
        st.caption(f"Showing latest 20 of {q('SELECT COUNT(*) AS n FROM Student').iloc[0]['n']:,} students")
        st.dataframe(stu_preview, use_container_width=True, hide_index=True)

    # ------------------------------------------------------------------
    # TAB 2 — ENROLL STUDENT
    # ------------------------------------------------------------------
    with admin_tabs[1]:
        st.markdown("#### Enroll a Student in a Course Offering")

        with st.form("form_enroll", clear_on_submit=True):
            col1, col2 = st.columns(2)
            with col1:
                enroll_sid = st.text_input("Student ID *", placeholder="e.g. UG2026101")
            with col2:
                offering_label = st.selectbox("Course Offering *", list(offering_options.keys()))

            enroll_date = st.date_input("Enrollment Date *", value=date.today())
            enroll_status = st.selectbox("Enrollment Status", ["Active", "Dropped", "Completed", "Failed"])
            submitted_e = st.form_submit_button("📋 Enroll Student", type="primary",
                                                 use_container_width=True)

        if submitted_e:
            if not enroll_sid.strip():
                st.error("Student ID is required.")
            else:
                off_id = offering_options[offering_label]
                ok, err = run_write(
                    """INSERT INTO Enrollment (StudentID, CourseOfferingID, EnrollmentDate, EnrollmentStatus)
                       VALUES (:1,:2,:3,:4)""",
                    (enroll_sid.strip(), off_id, enroll_date, enroll_status)
                )
                if ok:
                    st.success(f"✅ Student **{enroll_sid}** enrolled in **{offering_label}**.")
                else:
                    if "unique" in err.lower():
                        st.error(f"❌ Student {enroll_sid} is already enrolled in this offering.")
                    elif "foreign" in err.lower():
                        st.error(f"❌ Student ID not found. Register the student first.")
                    else:
                        st.error(f"❌ {err}")

        st.divider()
        st.markdown("##### Recent Enrollments")
        enroll_preview = q("""
            SELECT e.EnrollmentID, e.StudentID,
                   s.FirstName || ' ' || s.LastName AS StudentName,
                   c.CourseCode, c.CourseTitle,
                   co.AcademicYear, e.EnrollmentStatus, e.EnrollmentDate
            FROM Enrollment e
            JOIN Student s ON s.StudentID = e.StudentID
            JOIN CourseOffering co ON co.CourseOfferingID = e.CourseOfferingID
            JOIN Course c ON c.CourseID = co.CourseID
            ORDER BY e.EnrollmentID DESC LIMIT 15
        """)
        st.dataframe(enroll_preview, use_container_width=True, hide_index=True)

    # ------------------------------------------------------------------
    # TAB 3 — RECORD ASSESSMENT
    # ------------------------------------------------------------------
    with admin_tabs[2]:
        st.markdown("#### Record Assessment Result")
        st.caption("Requires an existing EnrollmentID. Use the Enrollment tab or Data Explorer to find it.")

        with st.form("form_assessment", clear_on_submit=True):
            col1, col2 = st.columns(2)
            with col1:
                enrollment_id = st.number_input("Enrollment ID *", min_value=1, step=1)
                cw_score = st.number_input("Coursework Score (0–100) *",
                                           min_value=0.0, max_value=100.0, step=0.5, value=0.0)
            with col2:
                exam_score = st.number_input("Exam Score (0–100) *",
                                             min_value=0.0, max_value=100.0, step=0.5, value=0.0)
                final_grade = st.selectbox("Final Grade *",
                                           ["A", "B+", "B", "C+", "C", "D+", "D", "F", "I"])

            submitted_a = st.form_submit_button("📝 Save Result", type="primary",
                                                 use_container_width=True)

        if submitted_a:
            weighted = 0.4 * cw_score + 0.6 * exam_score
            st.info(f"Weighted mark (40% CW + 60% Exam): **{weighted:.2f}**")
            ok, err = run_write(
                """INSERT INTO AssessmentResult (EnrollmentID, CourseworkScore, ExamScore, FinalGrade)
                   VALUES (:1,:2,:3,:4)""",
                (int(enrollment_id), cw_score, exam_score, final_grade)
            )
            if ok:
                st.success(f"✅ Assessment result saved for Enrollment #{enrollment_id}.")
            else:
                if "unique" in err.lower():
                    st.error(f"❌ A result for Enrollment #{enrollment_id} already exists.")
                elif "foreign" in err.lower():
                    st.error(f"❌ EnrollmentID {enrollment_id} not found.")
                else:
                    st.error(f"❌ {err}")

    # ------------------------------------------------------------------
    # TAB 4 — RECORD PAYMENT
    # ------------------------------------------------------------------
    with admin_tabs[3]:
        st.markdown("#### Record a Fee Payment")

        with st.form("form_payment", clear_on_submit=True):
            col1, col2 = st.columns(2)
            with col1:
                pay_sid = st.text_input("Student ID *", placeholder="e.g. UG2026001")
                amount = st.number_input("Amount Paid (GHS) *", min_value=0.0, step=50.0, value=0.0)
            with col2:
                pay_method = st.selectbox("Payment Method *", ["Mobile Money", "Bank", "Card", "Cash"])
                pay_date = st.date_input("Payment Date *", value=date.today())
                balance = st.number_input("Remaining Balance (GHS)",
                                          min_value=0.0, step=50.0, value=0.0,
                                          help="Outstanding amount after this payment")

            submitted_p = st.form_submit_button("💵 Record Payment", type="primary",
                                                  use_container_width=True)

        if submitted_p:
            if not pay_sid.strip():
                st.error("Student ID is required.")
            elif amount <= 0:
                st.error("Amount must be greater than 0.")
            else:
                ok, err = run_write(
                    """INSERT INTO FeePayment (StudentID, AmountPaid, PaymentDate, PaymentMethod, Balance)
                       VALUES (:1,:2,:3,:4,:5)""",
                    (pay_sid.strip(), amount, pay_date, pay_method, balance)
                )
                if ok:
                    st.success(f"✅ Payment of GHS {amount:,.2f} recorded for student {pay_sid}.")
                else:
                    if "foreign" in err.lower():
                        st.error(f"❌ Student ID {pay_sid} not found.")
                    else:
                        st.error(f"❌ {err}")

        st.divider()
        st.markdown("##### Recent Payments")
        pay_preview = q("""
            SELECT f.PaymentID, f.StudentID,
                   s.FirstName || ' ' || s.LastName AS StudentName,
                   f.AmountPaid, f.Balance, f.PaymentMethod, f.PaymentDate
            FROM FeePayment f
            JOIN Student s ON s.StudentID = f.StudentID
            ORDER BY f.PaymentID DESC LIMIT 15
        """)
        st.dataframe(pay_preview, use_container_width=True, hide_index=True,
                     column_config={
                         "AmountPaid": st.column_config.NumberColumn(format="GHS %.2f"),
                         "Balance": st.column_config.NumberColumn(format="GHS %.2f"),
                     })

    # ------------------------------------------------------------------
    # TAB 5 — ADD COURSE OFFERING
    # ------------------------------------------------------------------
    with admin_tabs[4]:
        st.markdown("#### Add a New Course Offering")

        course_df = q("SELECT CourseID, CourseCode, CourseTitle FROM Course ORDER BY CourseCode")
        course_options = {f"{r['coursecode']} – {r['coursetitle']}": r["courseid"]
                          for _, r in course_df.iterrows()}

        lecturer_df = q("SELECT LecturerID, LecturerName, Rank FROM Lecturer ORDER BY LecturerName")
        lec_options = {f"{r['lecturername']} ({r['rank']})": r["lecturerid"]
                       for _, r in lecturer_df.iterrows()}

        semester_df = q("SELECT SemesterID, SemesterName FROM Semester ORDER BY SemesterID")
        sem_options = {r["semestername"]: r["semesterid"] for _, r in semester_df.iterrows()}

        with st.form("form_offering", clear_on_submit=True):
            col1, col2 = st.columns(2)
            with col1:
                sel_course = st.selectbox("Course *", list(course_options.keys()))
                sel_lec = st.selectbox("Lecturer *", list(lec_options.keys()))
            with col2:
                sel_sem = st.selectbox("Semester *", list(sem_options.keys()))
                acad_year = st.text_input("Academic Year *", placeholder="e.g. 2025/2026",
                                          value="2025/2026")

            submitted_o = st.form_submit_button("📚 Create Offering", type="primary",
                                                  use_container_width=True)

        if submitted_o:
            if not acad_year.strip():
                st.error("Academic Year is required.")
            else:
                ok, err = run_write(
                    """INSERT INTO CourseOffering (CourseID, LecturerID, SemesterID, AcademicYear)
                       VALUES (:1,:2,:3,:4)""",
                    (course_options[sel_course], lec_options[sel_lec],
                     sem_options[sel_sem], acad_year.strip())
                )
                if ok:
                    st.success(f"✅ Course offering created: **{sel_course}** for {acad_year}.")
                else:
                    if "unique" in err.lower():
                        st.error("❌ This course offering already exists for the selected semester/year.")
                    else:
                        st.error(f"❌ {err}")

    # ------------------------------------------------------------------
    # TAB 6 — MANAGE / DELETE RECORDS
    # ------------------------------------------------------------------
    with admin_tabs[5]:
        st.markdown("#### 🗑️ Remove a Student Record")
        st.warning(
            "⚠️ **Caution:** Deleting a student will cascade-delete all related enrollments, "
            "assessment results, payments and LMS activity. This action cannot be undone."
        )

        with st.form("form_delete_student", clear_on_submit=True):
            del_sid = st.text_input("Student ID to delete *")
            confirm = st.checkbox("I confirm I want to permanently delete this student and all related records.")
            submitted_del = st.form_submit_button("🗑️ Delete Student", type="primary")

        if submitted_del:
            if not del_sid.strip():
                st.error("Please enter a Student ID.")
            elif not confirm:
                st.error("You must tick the confirmation checkbox.")
            else:
                check = q(f"SELECT StudentID, FirstName, LastName FROM Student WHERE StudentID = '{del_sid.strip()}'")
                if check.empty:
                    st.error(f"❌ Student ID '{del_sid}' not found.")
                else:
                    name = f"{check.iloc[0]['firstname']} {check.iloc[0]['lastname']}"
                    ok, err = run_write(
                        "DELETE FROM Student WHERE StudentID = :1",
                        (del_sid.strip(),)
                    )
                    if ok:
                        st.success(f"✅ Student **{name}** ({del_sid}) and all related records deleted.")
                    else:
                        st.error(f"❌ {err}")

        st.divider()
        st.markdown("#### Update Student Status")

        with st.form("form_update_status", clear_on_submit=True):
            upd_sid = st.text_input("Student ID *")
            new_status = st.selectbox("New Status *", ["Active", "Suspended", "Graduated", "Withdrawn"])
            submitted_upd = st.form_submit_button("✏️ Update Status", type="primary")

        if submitted_upd:
            if not upd_sid.strip():
                st.error("Student ID is required.")
            else:
                ok, err = run_write(
                    "UPDATE Student SET Status = :1 WHERE StudentID = :2",
                    (new_status, upd_sid.strip())
                )
                if ok:
                    st.success(f"✅ Status of student **{upd_sid}** updated to **{new_status}**.")
                else:
                    st.error(f"❌ {err}")


# =====================================================================
# FOOTER
# =====================================================================
st.divider()
st.caption(
    "Built by the GADMS team · DSCD 606 Data Management Techniques · "
    "University of Ghana · MPhil Data Science 2026"
)
