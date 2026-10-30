# 18 — VPS Kurulum ve Canlıya Geçiş Kılavuzu (Runbook)

> Bu belge, Nutopiano için temin edilecek yeni ve bağımsız Ubuntu 24.04 LTS VPS sunucusunun sıfırdan kurulması, sertleştirilmesi, Docker/Compose, pgBackRest, Nginx, Let's Encrypt ve Cloudflare yapılandırmasını komut komut içerir.
> **SERENUT İLE HİÇBİR ORTAK BAĞLANTI YOKTUR.**

---

## 1. SUNUCU İLK HAZIRLIK & SERTLEŞTİRME

### 1.1 Temel Güncellemeler ve Güvenlik
```bash
# SSH ile sunucuya root olarak bağlanın
ssh root@<VPS_IP>

# Paketleri güncelleyin
apt-get update && apt-get upgrade -y
apt-get install -y ufw fail2ban curl git jq htop chrony unattended-upgrades ca-certificates gnupg

# Zaman senkronizasyonunu kontrol edin (Europe/Istanbul)
timedatectl set-timezone Europe/Istanbul
systemctl restart chrony
timedatectl status
```

### 1.2 Deploy Kullanıcısı ve SSH Anahtarı
```bash
# deploy kullanıcısını oluşturun
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy

# deploy kullanıcısı için SSH anahtar dizini
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
cat << 'EOF' > /home/deploy/.ssh/authorized_keys
<SIZIN_PUBLIC_SSH_KEYINIZ>
EOF
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh

# Şifresiz sudo (yalnızca dağıtım kolaylığı için kısıtlı)
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
```

### 1.3 SSH ve UFW Güvenlik Duvarı
```bash
# SSH şifre girişini kapatın ve root girişini engelleyin
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Güvenlik Duvarı (UFW) Yapılandırması
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP (Cloudflare)'
ufw allow 443/tcp comment 'HTTPS (Cloudflare)'
ufw --force enable
ufw status verbose
```

---

## 2. DOCKER & DOCKER COMPOSE KURULUMU

```bash
# Resmî Docker GPG anahtarı ve deposu
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# deploy kullanıcısını docker grubuna ekleyin
usermod -aG docker deploy

# Docker daemon log boyutlandırması (/etc/docker/daemon.json)
cat << 'EOF' > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker
```

---

## 3. PROJE DİZİNİ VE YEDEK ALTYAPISI

```bash
# Kalıcı veri ve proje dizinlerini açın
mkdir -p /srv/nuto/{pgdata,media,backups,config,secrets}
chown -R deploy:deploy /srv/nuto
chmod 700 /srv/nuto/secrets

# dbmate kurulumu (Göç aracı)
curl -fsSL -o /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64
chmod +x /usr/local/bin/dbmate
```

---

## 4. DOCKER COMPOSE ÜRETİM DOSYASI (`/srv/nuto/docker-compose.yml`)

```yaml
version: '3.8'

networks:
  edge:
    driver: bridge
  internal:
    internal: true

services:
  db:
    image: postgres:17-alpine
    container_name: nuto-db
    restart: always
    environment:
      POSTGRES_USER: nuto_user
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
      POSTGRES_DB: nutopia_prod
    volumes:
      - /srv/nuto/pgdata:/var/lib/postgresql/data
      - /srv/nuto/config/pg_hba.conf:/etc/postgresql/pg_hba.conf:ro
    networks:
      - internal
    secrets:
      - db_password
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1024M

  api:
    image: ghcr.io/nutopia/api:${API_TAG:-latest}
    container_name: nuto-api
    restart: always
    env_file: /srv/nuto/config/api.env
    depends_on:
      - db
    volumes:
      - /srv/nuto/media:/srv/nuto/media
    networks:
      - internal
      - edge
    deploy:
      resources:
        limits:
          cpus: '0.8'
          memory: 512M

  web:
    image: ghcr.io/nutopia/web:${WEB_TAG:-latest}
    container_name: nuto-web
    restart: always
    env_file: /srv/nuto/config/web.env
    depends_on:
      - api
    networks:
      - edge
    deploy:
      resources:
        limits:
          cpus: '0.8'
          memory: 512M

  nginx:
    image: nginx:stable-alpine
    container_name: nuto-nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /srv/nuto/config/nginx.conf:/etc/nginx/nginx.conf:ro
      - /srv/nuto/config/ssl:/etc/ssl/nutopia:ro
      - /srv/nuto/media:/var/www/media:ro
      - /srv/nuto/admin_dist:/var/www/admin:ro
    networks:
      - edge
    depends_on:
      - web
      - api

secrets:
  db_password:
    file: /srv/nuto/secrets/db_password.txt
```

---

## 5. NGINX & GÜVENLİK YAPILANDIRMASI (`/srv/nuto/config/nginx.conf`)

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Gerçek IP Algılama (Cloudflare)
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 131.0.72.0/22;
    real_ip_header CF-Connecting-IP;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml image/svg+xml;

    # Rate Limiting Bölgeleri
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=20r/s;
    limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=5r/m;

    # 1. nutopiano.com ve www (Next.js Vitrin)
    server {
        listen 80;
        server_name nutopiano.com www.nutopiano.com;
        return 301 https://nutopiano.com$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name www.nutopiano.com;
        ssl_certificate /etc/ssl/nutopia/nutopiano.crt;
        ssl_certificate_key /etc/ssl/nutopia/nutopiano.key;
        return 301 https://nutopiano.com$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name nutopiano.com;

        ssl_certificate /etc/ssl/nutopia/nutopiano.crt;
        ssl_certificate_key /etc/ssl/nutopia/nutopiano.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        location /media/ {
            alias /var/www/media/;
            expires 30d;
            add_header Cache-Control "public, no-transform";
        }

        location / {
            proxy_pass http://web:3000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    # 2. api.nutopiano.com (NestJS API)
    server {
        listen 443 ssl http2;
        server_name api.nutopiano.com;

        ssl_certificate /etc/ssl/nutopia/nutopiano.crt;
        ssl_certificate_key /etc/ssl/nutopia/nutopiano.key;

        client_max_body_size 15M;

        location /v1/auth/ {
            limit_req zone=auth_limit burst=5 nodelay;
            proxy_pass http://api:3001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location / {
            limit_req zone=api_limit burst=40 nodelay;
            proxy_pass http://api:3001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }

    # 3. admin.nutopiano.com (Yönetim & Şoför SPA)
    server {
        listen 443 ssl http2;
        server_name admin.nutopiano.com;

        ssl_certificate /etc/ssl/nutopia/nutopiano.crt;
        ssl_certificate_key /etc/ssl/nutopia/nutopiano.key;

        root /var/www/admin;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
```

---

## 6. DAĞITIM VE YAYINLAMA BETİĞİ (`/srv/nuto/deploy.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

cd /srv/nuto

echo "=== [1/5] Göçler Çalıştırılıyor (dbmate) ==="
export DATABASE_URL="postgres://nuto_user:$(cat /srv/nuto/secrets/db_password.txt)@127.0.0.1:5432/nutopia_prod?sslmode=disable"
dbmate --no-dump-schema up

echo "=== [2/5] Yeni Docker İmajları Çekiliyor ==="
docker compose pull api web

echo "=== [3/5] Sıfır Kesintiyle Konteynerler Yenileniyor ==="
docker compose up -d --remove-orphans

echo "=== [4/5] Sağlık Kontrolü Yapılıyor ==="
sleep 5
curl -fsS http://127.0.0.1:80/health/ready || (echo "HATA: Servisler ayakta değil!" && exit 1)

echo "=== [5/5] Eski İmajlar Temizleniyor ==="
docker image prune -f

echo "=== DAĞITIM BAŞARIYLA TAMAMLANDI ==="
```

---

## 7. YEDEKLEME VE WAL ARŞİVLEME ÇALIŞTIRMA KONTROLÜ

```bash
# Günlük crontab tanımı (deploy kullanıcısı ile)
# crontab -e
# Her gece 03:00'te PostgreSQL tam yedeği ve uzak depoya restic aktarımı
0 3 * * * /srv/nuto/scripts/backup-nightly.sh >> /srv/nuto/backups/backup.log 2>&1
```

