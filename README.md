# GADMS Analytics Dashboard + Admin Backend

**Governed Academic Data Management System**  
DSCD 606 Data Management Techniques · University of Ghana · MPhil Data Science 2026

---

## What it does

A live analytics dashboard **and** a write-capable admin backend for the GADMS PostgreSQL schema.  
Every record added through the Admin panel instantly updates every chart and KPI on the dashboard — no manual refresh needed.

| Tab | What it shows |
|---|---|
| 📊 Overview | Students per programme, gender split, status distribution |
| 🎯 Performance | Avg weighted mark, grade distribution, coursework vs exam scatter |
| 💻 LMS Engagement | Minutes vs events by grade — surfaces at-risk students |
| 💰 Finance | Payment-method volumes, outstanding-balance worklist |
| 🗂️ Data Explorer | Browse any of the 12 tables, download as CSV |
| 🧪 Query Lab | Read-only free-form SQL |
| ⚙️ Admin | **Add students, enroll, record grades, payments, manage records** |

---

## Two running modes

| Mode | Badge | Admin writes? |
|---|---|---|
| **Postgres (live)** — `DATABASE_URL` configured | 🟢 green | ✅ Yes — changes are instant |
| **DuckDB (embedded demo)** — no URL configured | 🦆 yellow | ❌ Read-only demo |

---

## Deploy free in under 20 minutes (Supabase + Streamlit Cloud)

### Step 1 — Create a free Postgres database on Supabase

1. Sign up at <https://supabase.com> → **New Project** (free tier = permanent Postgres).  
2. In the **SQL Editor**, paste the entire contents of `TEAM_ALPHA.sql` and click **Run**.  
   Your 12 tables and 1,000+ sample records load in seconds.  
3. Go to **Project Settings → Database → Connection string → URI**.  
   Copy the URI — it looks like:  
   ```
   postgresql://postgres:YOUR_PASSWORD@db.xxxxxxxxxxxx.supabase.co:5432/postgres
   ```

### Step 2 — Push this repo to GitHub

```bash
git init
git add .
git commit -m "GADMS dashboard with admin backend"
gh repo create gadms-dashboard --public --source=. --push
```

> **Important:** `.streamlit/secrets.toml` is in `.gitignore` — it is **never** committed.  
> Your credentials go into Streamlit Cloud secrets only (see Step 3).

### Step 3 — Deploy to Streamlit Community Cloud

1. Go to <https://share.streamlit.io> → **New app** → pick your GitHub repo → main file `app.py`.  
2. Click **Advanced settings → Secrets** and paste:

```toml
DATABASE_URL   = "postgresql://postgres:YOUR_PASSWORD@db.xxxx.supabase.co:5432/postgres"
ADMIN_PASSWORD = "YourSecurePassword"
```

3. Click **Deploy**. You get a public URL like `https://gadms-yourhandle.streamlit.app`.  
4. The badge turns **🟢 Postgres (live)** and the Admin tab becomes fully writable.

---

## Admin panel usage

Navigate to the **⚙️ Admin** tab on the deployed dashboard.

### Login
Enter your `ADMIN_PASSWORD` (set in Streamlit secrets; defaults to `gadms2026`).

### Add Student
Fill in Student ID, name, programme, gender, email, admission year and status.  
Click **Register Student** — the student count KPI updates within seconds.

### Enroll Student
Pick a student ID and a course offering from the dropdowns.  
The enrollment table and LMS tab charts update immediately.

### Record Assessment Result
Enter the Enrollment ID (find it in Data Explorer → Enrollment table),  
coursework score, exam score and final grade.  
The Performance tab charts update on the next render.

### Record Fee Payment
Enter Student ID, amount, payment method and outstanding balance.  
The Finance tab updates immediately.

### Add Course Offering
Link a course, lecturer and semester to create a new offering.  
The new offering appears in the Enroll Student dropdown instantly.

### Manage Records
Update a student's status or permanently delete a student  
(cascade-deletes all related enrollments, results, payments and LMS logs).

---

## How instant updates work

The app uses `@st.cache_data(ttl=30)` — a 30-second cache on all read queries.  
Admin write operations call `q.clear()` immediately after a successful INSERT/UPDATE/DELETE,  
so the next render fetches fresh data from Postgres — no page reload required.

---

## Project structure

```
gadms-dashboard/
├── app.py                        # Dashboard + Admin backend (single file)
├── TEAM_ALPHA.sql                # Full schema + 1,000+ records (PostgreSQL DDL/DML)
├── requirements.txt
├── .streamlit/
│   ├── config.toml               # Theme + headless server settings
│   └── secrets.toml.example      # Template — copy to secrets.toml locally
├── .gitignore                    # Excludes secrets.toml
└── README.md
```

---

## Local development (optional)

```bash
git clone <your-repo-url>
cd gadms-dashboard
pip install -r requirements.txt

# Option A: read-only demo (no DB needed)
streamlit run app.py

# Option B: full live mode with admin writes
cp .streamlit/secrets.toml.example .streamlit/secrets.toml
# Edit secrets.toml — paste your DATABASE_URL and ADMIN_PASSWORD
streamlit run app.py
```

---

## Tech stack

| Layer | Technology |
|---|---|
| Frontend / UI | Streamlit 1.36+ |
| Charts | Plotly Express |
| Data manipulation | pandas |
| Production database | PostgreSQL 13+ (Supabase) |
| Demo fallback | DuckDB in-memory |
| ORM / driver | SQLAlchemy + psycopg2 |
| Hosting | Streamlit Community Cloud |
| Version control | Git / GitHub |

---

## Credits

Built by **Team Alpha** as a portfolio extension of the DSCD 606 mini project —  
Designed a Governed Academic Data Management System.

University of Ghana · School of Physical and Mathematical Sciences  
Department of Computer Science · MPhil Data Science · 2026  
Course Instructor: Prof. Kofi Sarpong Adu-Manu
