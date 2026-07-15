docker exec -i serenut-db psql -U serenut_user -d serenut_db -c "ALTER USER serenut_user WITH PASSWORD 'dbpass123';"
docker restart serenut-backend
