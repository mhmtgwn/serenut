KEY=$(openssl genrsa 2048 | awk '1' ORS='\n')
echo "RSA_PRIVATE_KEY="$KEY"" >> /var/www/serenut/server/.env.production
cd /var/www/serenut/server
docker compose -f docker-compose.prod.yml restart backend
