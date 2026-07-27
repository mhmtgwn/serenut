import re

nginx_file = '/etc/nginx/sites-available/serenut'

with open(nginx_file, 'r', encoding='utf-8') as f:
    conf = f.read()

# Add map $http_upgrade $connection_upgrade if missing
map_block = """map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
"""

if 'map $http_upgrade $connection_upgrade' not in conf:
    conf = map_block + '\n' + conf

# Replace fixed Connection 'upgrade' with dynamic $connection_upgrade
conf = conf.replace("proxy_set_header Connection 'upgrade';", "proxy_set_header Connection $connection_upgrade;")
conf = conf.replace('proxy_set_header Connection "Upgrade";', "proxy_set_header Connection $connection_upgrade;")

# Remove old 301 redirect locations for login, signup, register
redirect_pattern = r'location\s*=\s*/(login|login\.html|signup|signup\.html|register|register\.html|reset-password)\s*\{[^}]*\}'
conf = re.sub(redirect_pattern, '', conf)
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

print("NGINX_WEBSOCKET_AND_SPA_CONFIG_UPDATED")
