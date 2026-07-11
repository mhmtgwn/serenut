#!/usr/bin/env bash
# server/scripts/chaos-monkey.sh
# Serenut OS — Lightweight SRE Chaos Monkey Daemon
# Blueprint: Enterprise Certification (Chaos Engineering)

echo "🐒 Chaos Monkey daemon started. Preparing random service disruptions..."

SERVICES=("serenut-redis" "serenut-backend" "serenut-db")

while true; do
  # Disruption interval: 30 minutes (1800 seconds)
  # For manual execution verification, can be run on shorter durations
  INTERVAL=${CHAOS_INTERVAL_SECONDS:-1800}
  echo "⏱️ Waiting for ${INTERVAL} seconds before next disruption..."
  sleep ${INTERVAL}
  
  # Select a random service to disrupt
  TARGET=${SERVICES[$RANDOM % ${#SERVICES[@]}]}
  
  echo "💥 [Chaos Monkey] Disruption triggered! Killing container: ${TARGET}"
  
  # Kill container forcefully
  docker compose -f docker-compose.prod.yml kill ${TARGET}
  
  if [ $? -eq 0 ]; then
    echo "🚨 [Chaos Monkey] Successfully killed ${TARGET}."
  else
    echo "⚠️ [Chaos Monkey] Failed to kill ${TARGET} (might not be running)."
  fi
  
  # Wait 10 seconds (failure window)
  echo "⏳ Simulating failure window (10 seconds)..."
  sleep 10
  
  # Recover container
  echo "🔄 [Chaos Monkey] Triggering recovery. Starting container: ${TARGET}"
  docker compose -f docker-compose.prod.yml start ${TARGET}
  
  if [ $? -eq 0 ]; then
    echo "✅ [Chaos Monkey] Recovery started for ${TARGET}."
  else
    echo "❌ [Chaos Monkey] Recovery failed for ${TARGET}!"
  fi
done
