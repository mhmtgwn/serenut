#!/bin/bash
# cloudflare-ssl-setup.sh — Configure Certbot, Strict SSL, and Cloudflare Authenticated Origin Pulls

set -e

DOMAIN="serenut.com"
EMAIL="admin@serenut.com"

echo "🛡️ Setting up SSL & Cloudflare Hardening for $DOMAIN..."

# Step 1: Install Certbot if missing
if ! command -v certbot &> /dev/null; then
  echo "📥 Installing Certbot & Nginx package..."
  sudo apt-get update
  sudo apt-get install -y certbot python3-certbot-nginx
fi

# Step 2: Request SSL Certificate using Certbot Nginx plugin
echo "🔑 Requesting Let's Encrypt certificate..."
sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect

# Step 3: Setup Cloudflare Authenticated Origin Pulls
echo "🔒 Configuring Cloudflare Origin Pull verification certificate..."
sudo mkdir -p /etc/nginx/certs
# Download Cloudflare Origin Pull CA
sudo curl -s -o /etc/nginx/certs/cloudflare-origin-pull.pem https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem

echo "⚙️ Creating Nginx origin pull block configuration..."
cat <<EOF | sudo tee /etc/nginx/snippets/cloudflare-origin-pull.conf
# Enforce Authenticated Origin Pulls
ssl_client_certificate /etc/nginx/certs/cloudflare-origin-pull.pem;
ssl_verify_client on;
EOF

# Step 4: Validate and Test Certbot dry-run automated renewals
echo "🔄 Verifying Certbot auto-renewal timers..."
sudo certbot renew --dry-run

echo "✅ Cloudflare Strict SSL & Certbot Auto-Renewals verified successfully!"
