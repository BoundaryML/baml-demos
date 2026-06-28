"""Sample-data seeding, ported from the Mastra `database-seeding-tool`.

Pure I/O + data generation — exactly the kind of work that belongs in the Python
bridge rather than in BAML. Creates ten related business tables (companies,
locations, departments, job_titles, employees, skills, employee_skills, projects,
project_assignments, salary_history) and fills them with realistic, randomized data
so the text-to-SQL demo has interesting multi-table joins to query.
"""

from __future__ import annotations

import random
from datetime import date, timedelta

from baml_sdk import SeedResult

COMPANIES = [
    (1, "TechCorp Solutions", "Technology", 2015, 1200, 150_000_000, "San Francisco, CA"),
    (2, "Global Finance Inc", "Financial Services", 2008, 800, 95_000_000, "New York, NY"),
    (3, "Green Energy Systems", "Renewable Energy", 2018, 450, 62_000_000, "Austin, TX"),
    (4, "Healthcare Plus", "Healthcare", 2012, 650, 78_000_000, "Boston, MA"),
    (5, "EduTech Solutions", "Education Technology", 2020, 280, 28_000_000, "Seattle, WA"),
]

LOCATIONS = [
    (1, 1, "San Francisco HQ", "123 Tech Street", "San Francisco", "CA", "USA", "Headquarters"),
    (2, 1, "Austin Branch", "456 Innovation Blvd", "Austin", "TX", "USA", "Branch"),
    (3, 2, "New York HQ", "789 Wall Street", "New York", "NY", "USA", "Headquarters"),
    (4, 2, "London Office", "10 Finsbury Square", "London", "England", "UK", "International"),
    (5, 3, "Austin HQ", "321 Green Way", "Austin", "TX", "USA", "Headquarters"),
    (6, 4, "Boston HQ", "555 Medical Drive", "Boston", "MA", "USA", "Headquarters"),
    (7, 5, "Seattle HQ", "777 Learning Lane", "Seattle", "WA", "USA", "Headquarters"),
]

DEPARTMENTS = [
    (1, 1, "Engineering", 5_000_000, 10),
    (2, 1, "Product Management", 1_200_000, 10),
    (3, 1, "Sales", 2_800_000, 10),
    (4, 1, "Marketing", 1_800_000, 20),
    (5, 1, "Human Resources", 900_000, 15),
    (6, 2, "Investment Banking", 8_000_000, 20),
    (7, 2, "Risk Management", 1_500_000, 45),
    (8, 2, "Compliance", 1_200_000, 30),
    (9, 3, "Research & Development", 3_500_000, 25),
    (10, 3, "Operations", 2_200_000, 10),
    (11, 4, "Clinical Research", 4_200_000, 25),
    (12, 4, "Regulatory Affairs", 1_800_000, 15),
    (13, 5, "Software Development", 2_500_000, 25),
    (14, 5, "Content Creation", 800_000, 20),
]

# (id, title, level, department_type)
JOB_TITLES = [
    (1, "Software Engineer", "Mid", "Engineering"),
    (2, "Senior Software Engineer", "Senior", "Engineering"),
    (3, "Staff Software Engineer", "Staff", "Engineering"),
    (4, "Engineering Manager", "Management", "Engineering"),
    (5, "Product Manager", "Mid", "Product Management"),
    (6, "Senior Product Manager", "Senior", "Product Management"),
    (7, "Sales Representative", "Junior", "Sales"),
    (8, "Senior Sales Representative", "Senior", "Sales"),
    (9, "Sales Manager", "Management", "Sales"),
    (10, "Marketing Specialist", "Mid", "Marketing"),
    (11, "Marketing Manager", "Management", "Marketing"),
    (12, "HR Business Partner", "Senior", "Human Resources"),
    (13, "Investment Banker", "Senior", "Investment Banking"),
    (14, "Risk Analyst", "Mid", "Risk Management"),
    (15, "Research Scientist", "Senior", "Research & Development"),
    (16, "Clinical Researcher", "Senior", "Clinical Research"),
    (17, "Data Scientist", "Senior", "Engineering"),
    (18, "DevOps Engineer", "Mid", "Engineering"),
    (19, "UX Designer", "Mid", "Product Management"),
    (20, "Content Writer", "Junior", "Content Creation"),
]

SKILLS = [
    (1, "JavaScript", "Programming Language", "Intermediate"),
    (2, "Python", "Programming Language", "Intermediate"),
    (3, "React", "Frontend Framework", "Intermediate"),
    (4, "Node.js", "Backend Framework", "Intermediate"),
    (5, "SQL", "Database", "Intermediate"),
    (6, "PostgreSQL", "Database", "Advanced"),
    (7, "AWS", "Cloud Platform", "Advanced"),
    (8, "Docker", "DevOps", "Intermediate"),
    (9, "Kubernetes", "DevOps", "Advanced"),
    (10, "Machine Learning", "AI/ML", "Advanced"),
    (11, "Data Analysis", "Analytics", "Intermediate"),
    (12, "Project Management", "Management", "Intermediate"),
    (13, "Agile/Scrum", "Methodology", "Intermediate"),
    (14, "Java", "Programming Language", "Intermediate"),
    (15, "C++", "Programming Language", "Advanced"),
    (16, "Go", "Programming Language", "Advanced"),
    (17, "TypeScript", "Programming Language", "Intermediate"),
    (18, "Vue.js", "Frontend Framework", "Intermediate"),
    (19, "MongoDB", "Database", "Intermediate"),
    (20, "Redis", "Database", "Intermediate"),
]

_FIRST_NAMES = "John Jane Michael Sarah David Emily Robert Lisa Chris Amanda James Jennifer William Michelle Daniel Ashley Thomas Jessica Richard Nicole Mark Elizabeth Brian Anna Kevin Stephanie Paul Rachel Steven Lauren".split()
_LAST_NAMES = "Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor Moore Jackson Martin Lee Perez Thompson White Harris Sanchez Clark Ramirez Lewis Robinson".split()

_DEPT_MULTIPLIERS = {
    "Engineering": 1.2,
    "Investment Banking": 1.8,
    "Product Management": 1.3,
    "Sales": 1.1,
    "Clinical Research": 1.4,
    "Risk Management": 1.3,
    "Research & Development": 1.3,
}
_BASE_SALARY = {"Senior": 85_000, "Staff": 120_000, "Management": 130_000}

_DROP = [
    "salary_history", "project_assignments", "employee_skills", "projects",
    "employees", "skills", "job_titles", "departments", "locations", "companies",
]

_CREATE = [
    """CREATE TABLE companies (
        id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, industry VARCHAR(100),
        founded INTEGER, employees_count INTEGER, revenue BIGINT, headquarters VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)""",
    """CREATE TABLE locations (
        id SERIAL PRIMARY KEY, company_id INTEGER REFERENCES companies(id), name VARCHAR(255) NOT NULL,
        address VARCHAR(255), city VARCHAR(100), state VARCHAR(100), country VARCHAR(100),
        office_type VARCHAR(50), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)""",
    """CREATE TABLE departments (
        id SERIAL PRIMARY KEY, company_id INTEGER REFERENCES companies(id), name VARCHAR(255) NOT NULL,
        budget BIGINT, head_count INTEGER, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)""",
    """CREATE TABLE job_titles (
        id SERIAL PRIMARY KEY, title VARCHAR(255) NOT NULL, level VARCHAR(50),
        department_type VARCHAR(100), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)""",
    """CREATE TABLE employees (
        id SERIAL PRIMARY KEY, company_id INTEGER REFERENCES companies(id),
        department_id INTEGER REFERENCES departments(id), location_id INTEGER REFERENCES locations(id),
        job_title_id INTEGER REFERENCES job_titles(id), first_name VARCHAR(100) NOT NULL,
        last_name VARCHAR(100) NOT NULL, email VARCHAR(255) UNIQUE, phone VARCHAR(50), hire_date DATE,
        salary INTEGER, manager_id INTEGER REFERENCES employees(id), status VARCHAR(20) DEFAULT 'Active',
        birth_date DATE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)""",
    """CREATE TABLE skills (
        id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL UNIQUE, category VARCHAR(100),
        difficulty VARCHAR(50), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)""",
    """CREATE TABLE employee_skills (
        id SERIAL PRIMARY KEY, employee_id INTEGER REFERENCES employees(id),
        skill_id INTEGER REFERENCES skills(id), proficiency_level VARCHAR(50),
        years_experience INTEGER, certified BOOLEAN DEFAULT false, UNIQUE(employee_id, skill_id))""",
    """CREATE TABLE projects (
        id SERIAL PRIMARY KEY, company_id INTEGER REFERENCES companies(id), name VARCHAR(255) NOT NULL,
        description TEXT, start_date DATE, end_date DATE, budget BIGINT, status VARCHAR(50),
        priority VARCHAR(20), progress INTEGER DEFAULT 0, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)""",
    """CREATE TABLE project_assignments (
        id SERIAL PRIMARY KEY, project_id INTEGER REFERENCES projects(id),
        employee_id INTEGER REFERENCES employees(id), role VARCHAR(100), allocation_percentage INTEGER,
        start_date DATE, end_date DATE, UNIQUE(project_id, employee_id))""",
    """CREATE TABLE salary_history (
        id SERIAL PRIMARY KEY, employee_id INTEGER REFERENCES employees(id), salary INTEGER,
        effective_date DATE, reason VARCHAR(255), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)""",
]

_PROJECT_NAMES = [
    "Customer Portal Redesign", "Mobile App Development", "Data Analytics Platform", "Cloud Migration",
    "Security Enhancement", "Performance Optimization", "API Integration", "Machine Learning Pipeline",
    "Compliance Automation", "Business Intelligence Dashboard", "Microservices Architecture",
    "DevOps Automation", "User Experience Improvement", "Database Optimization", "Real-time Monitoring",
    "Automated Testing Suite", "Content Management System", "E-commerce Platform",
    "Financial Reporting Tool", "Customer Support Portal",
]
_STATUSES = ["Planning", "In Progress", "On Hold", "Completed", "Cancelled"]
_ROLES = ["Lead Developer", "Developer", "Designer", "Project Manager", "QA Engineer", "Business Analyst", "DevOps Engineer"]
_PROFICIENCY = ["Beginner", "Intermediate", "Advanced", "Expert"]
_REASONS = ["Annual Review", "Promotion", "Market Adjustment", "Performance Bonus", "Cost of Living Adjustment"]


def _rand_date(start_year: int, span_years: int) -> date:
    start = date(start_year, 1, 1)
    return start + timedelta(days=random.randint(0, span_years * 365))


def _generate_employees() -> list[tuple]:
    """Return employee rows (manager_id left NULL — wired up after insert)."""
    rows: list[tuple] = []
    eid = 1
    company_name = {c[0]: c[1].lower().replace(" ", "") for c in COMPANIES}
    for dep_id, comp_id, dep_name, _budget, head_count in DEPARTMENTS:
        # Software Development draws from Engineering titles (matches the Mastra
        # special case); otherwise fall back to the full pool when none match.
        match_type = "Engineering" if dep_name == "Software Development" else dep_name
        titles = [jt for jt in JOB_TITLES if jt[3] == match_type] or JOB_TITLES
        location = next((l for l in LOCATIONS if l[1] == comp_id), LOCATIONS[0])
        for _ in range(int(head_count * 0.8)):
            first, last = random.choice(_FIRST_NAMES), random.choice(_LAST_NAMES)
            jt = random.choice(titles)
            base = _BASE_SALARY.get(jt[2], 50_000)
            salary = int(base * _DEPT_MULTIPLIERS.get(dep_name, 1.0) * (0.9 + random.random() * 0.2))
            rows.append((
                eid, comp_id, dep_id, location[0], jt[0], first, last,
                f"{first.lower()}.{last.lower()}.{eid}@{company_name[comp_id]}.com",
                f"+1-{random.randint(100, 999)}-{random.randint(100, 999)}-{random.randint(1000, 9999)}",
                _rand_date(2018, 6), salary, None,
                "Active" if random.random() > 0.05 else "Inactive",
                _rand_date(1985, 15),
            ))
            eid += 1
    return rows


def _generate_projects() -> list[tuple]:
    rows: list[tuple] = []
    pid = 1
    for comp_id, name, *_ in COMPANIES:
        for _ in range(random.randint(5, 12)):
            start = _rand_date(2022, 3)
            end = start + timedelta(days=random.randint(0, 730))
            rows.append((
                pid, comp_id, random.choice(_PROJECT_NAMES),
                f"Strategic project for {name} focusing on business improvement and innovation",
                start, end, random.randint(100_000, 2_100_000), random.choice(_STATUSES),
                # 50% High / 25% Medium / 25% Low, matching the Mastra distribution.
                ("High" if random.random() > 0.5 else "Medium" if random.random() > 0.5 else "Low"),
                random.randint(0, 99),
            ))
            pid += 1
    return rows


def seed(conn) -> SeedResult:
    """Drop, recreate, and populate the full business dataset. Idempotent."""
    random.seed(42)  # reproducible demo data
    total = 0
    # Seed atomically: the shared connection runs in autocommit mode, so flip it
    # off for the duration and commit/rollback as one unit (no half-seeded DB).
    prev_autocommit = conn.autocommit
    conn.autocommit = False
    try:
      with conn.cursor() as cur:
        print("🏗️  Recreating tables...")
        for t in _DROP:
            cur.execute(f"DROP TABLE IF EXISTS {t} CASCADE")
        for ddl in _CREATE:
            cur.execute(ddl)

        cur.executemany(
            "INSERT INTO companies (id, name, industry, founded, employees_count, revenue, headquarters) VALUES (%s,%s,%s,%s,%s,%s,%s)",
            COMPANIES,
        )
        cur.executemany(
            "INSERT INTO locations (id, company_id, name, address, city, state, country, office_type) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
            LOCATIONS,
        )
        cur.executemany(
            "INSERT INTO departments (id, company_id, name, budget, head_count) VALUES (%s,%s,%s,%s,%s)",
            DEPARTMENTS,
        )
        cur.executemany(
            "INSERT INTO job_titles (id, title, level, department_type) VALUES (%s,%s,%s,%s)",
            JOB_TITLES,
        )
        cur.executemany(
            "INSERT INTO skills (id, name, category, difficulty) VALUES (%s,%s,%s,%s)",
            SKILLS,
        )
        total += len(COMPANIES) + len(LOCATIONS) + len(DEPARTMENTS) + len(JOB_TITLES) + len(SKILLS)

        employees = _generate_employees()
        cur.executemany(
            """INSERT INTO employees
               (id, company_id, department_id, location_id, job_title_id, first_name, last_name,
                email, phone, hire_date, salary, manager_id, status, birth_date)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            employees,
        )
        total += len(employees)
        print(f"📊 Inserted {len(employees)} employees")

        # Wire up manager relationships after all employees exist (avoids FK violations).
        mgr_level = {jt[0] for jt in JOB_TITLES if jt[2] == "Management"}
        by_dept: dict[int, list[tuple]] = {}
        for e in employees:
            by_dept.setdefault(e[2], []).append(e)
        for e in employees:
            if random.random() > 0.85:
                mgrs = [m for m in by_dept[e[2]] if m[0] != e[0] and m[4] in mgr_level]
                if mgrs:
                    cur.execute("UPDATE employees SET manager_id = %s WHERE id = %s", (random.choice(mgrs)[0], e[0]))

        # Employee skills (2-6 each).
        skill_rows = []
        for e in employees:
            for sk in random.sample(SKILLS, random.randint(2, 6)):
                skill_rows.append((e[0], sk[0], random.choice(_PROFICIENCY), random.randint(1, 8), random.random() > 0.7))
        cur.executemany(
            "INSERT INTO employee_skills (employee_id, skill_id, proficiency_level, years_experience, certified) VALUES (%s,%s,%s,%s,%s)",
            skill_rows,
        )
        total += len(skill_rows)

        projects = _generate_projects()
        cur.executemany(
            """INSERT INTO projects (id, company_id, name, description, start_date, end_date, budget, status, priority, progress)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            projects,
        )
        total += len(projects)

        # Project assignments (3-10 employees from the same company).
        assignments = []
        emp_by_company: dict[int, list[tuple]] = {}
        for e in employees:
            emp_by_company.setdefault(e[1], []).append(e)
        for p in projects:
            team = random.sample(emp_by_company.get(p[1], []), min(random.randint(3, 10), len(emp_by_company.get(p[1], []))))
            for e in team:
                assignments.append((p[0], e[0], random.choice(_ROLES), random.randint(25, 74), p[4], p[5]))
        cur.executemany(
            "INSERT INTO project_assignments (project_id, employee_id, role, allocation_percentage, start_date, end_date) VALUES (%s,%s,%s,%s,%s,%s)",
            assignments,
        )
        total += len(assignments)

        # Salary history (1-3 raises per employee).
        history = []
        for e in employees:
            current = int(e[10] * 0.8)  # e[10] = salary
            hire = e[9]                  # e[9]  = hire_date
            for i in range(random.randint(1, 3)):
                # Clamp Feb-29 hires so date() doesn't raise in non-leap years
                # (JS setFullYear rolls them to Mar-1; clamping to the 28th is close enough).
                day = min(hire.day, 28) if hire.month == 2 else hire.day
                eff = date(hire.year + i, hire.month, day)
                history.append((e[0], current, eff, random.choice(_REASONS)))
                current = int(current * (1.05 + random.randint(0, 1000) / 10000))
        cur.executemany(
            "INSERT INTO salary_history (employee_id, salary, effective_date, reason) VALUES (%s,%s,%s,%s)",
            history,
        )
        total += len(history)
      conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.autocommit = prev_autocommit

    print(f"🎉 Seeded {total} records")
    return SeedResult(
        success=True,
        message=f"Database seeded successfully with {total} records across 10 related tables",
        record_count=total,
        tables_created=list(reversed(_DROP)),
    )
