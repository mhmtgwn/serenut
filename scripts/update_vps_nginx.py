import re

nginx_file = '/etc/nginx/sites-available/serenut'

with open(nginx_file, 'r', encoding='utf-8') as f:
    conf = f.read()

# Remove old 301 redirect locations for login, signup, register
redirect_pattern = r'location\s*=\s*/(login|login\.html|signup|signup\.html|register|register\.html|reset-password)\s*\{[^}]*\}'
conf = re.sub(redirect_pattern, '', conf)

# Remove extra empty lines caused by removal
conf = re.sub(r'\n\s*\n\s*\n', '\n\n', conf)

new_routes = """
    # Clean SPA routing for auth & app without 301 redirect hacks
    location ~ ^/(login|register|signup|reset-password)$ {
        try_files /app/index.html =404;
    }

    location /app/ {
        try_files $uri $uri/ /app/index.html;
    }

    location = /app {
        try_files /app/index.html =404;
    }
"""

if 'location /shared/' in conf and 'location ~ ^/(login|register' not in conf:
    conf = conf.replace('location /shared/', new_routes.strip() + '\n\n    location /shared/')
    with open(nginx_file, 'w', encoding='utf-8') as f:
        f.write(conf)
    print("NGINX_SPA_ROUTES_UPDATED_SUCCESSFULLY")
else:
    print("Nginx config already updated or location target not found.")
