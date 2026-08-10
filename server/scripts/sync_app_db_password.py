#!/usr/bin/env python3
"""Synchronize the restricted PostgreSQL role password from .env.production."""
import re
import subprocess
from pathlib import Path

text = Path('.env.production').read_text(encoding='utf-8')
match = re.search(r'^DATABASE_URL=postgresql://serenut_app:([^@]+)@', text, re.MULTILINE)
if not match or not re.fullmatch(r'[0-9a-f]{64}', match.group(1)):
    raise SystemExit('restricted DATABASE_URL password is missing or malformed')

sql = "ALTER ROLE serenut_app PASSWORD '" + match.group(1) + "';\n"
subprocess.run(
    ['docker', 'exec', '-i', 'serenut-db', 'psql', '-v', 'ON_ERROR_STOP=1',
     '-U', 'serenut_user', '-d', 'serenut_db'],
    input=sql,
    text=True,
    check=True,
    stdout=subprocess.DEVNULL,
)
