import psycopg2

conn = psycopg2.connect("postgresql://serenut_user:SerenutSecurePass123!@127.0.0.1:5432/postgres")
cur = conn.cursor()
cur.execute("SELECT datname FROM pg_database WHERE datistemplate = false;")
dbs = [r[0] for r in cur.fetchall()]
print("EXISTING DATABASES:", dbs)

for db in dbs:
    try:
        c = psycopg2.connect(f"postgresql://serenut_user:SerenutSecurePass123!@127.0.0.1:5432/{db}")
        cr = c.cursor()
        cr.execute("SELECT tablename FROM pg_tables WHERE schemaname='public';")
        t = [r[0] for r in cr.fetchall()]
        print(f"DB '{db}' TABLES ({len(t)}):", t[:10])
    except Exception as e:
        print(f"DB '{db}' ERROR:", e)
