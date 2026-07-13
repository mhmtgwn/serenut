-- server/db/schema_v19.sql
-- Serenut OS — Device Fingerprints and Licensing hardening (Sprint 1)

CREATE TABLE IF NOT EXISTS device_fingerprints (
    device_id VARCHAR(255) PRIMARY KEY,
    installation_id VARCHAR(255) NOT NULL,
    machine_hash VARCHAR(255) NOT NULL,
    hardware_hash VARCHAR(255) NOT NULL,
    cpu_architecture VARCHAR(50),
    os_version TEXT,
    app_version VARCHAR(50),
    device_name VARCHAR(255),
    platform VARCHAR(50),
    install_date TIMESTAMP WITH TIME ZONE NOT NULL,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    hardware_change_count INT DEFAULT 0
);
