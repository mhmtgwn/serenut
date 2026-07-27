import subprocess

sql = "DELETE FROM app_versions WHERE id = 'rel-1785145088126';"
cmd = ["docker", "exec", "-i", "serenut-db", "psql", "-U", "serenut_user", "-d", "serenut_db", "-c", sql]
res = subprocess.run(cmd, capture_output=True, text=True)
print("STDOUT:", res.stdout)
print("STDERR:", res.stderr)
