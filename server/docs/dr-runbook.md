# Disaster Recovery Runbook

**Serenut OS — Versiyon 1.0 | Son Güncelleme: 2026-07**

---

## Hedefler

- **RPO (Recovery Point Objective):** 24 saat (Günlük yedekleme)
- **RTO (Recovery Time Objective):** 4 saat (Kurtarma süresi)
- **Fire Drill Sıklığı:** Her 3 ayda bir gerçekleştirilir.

---

## 1. Yedekleme Prosedürü

Yedeklemeler her gece saat 02:00'de `devops/backup.sh` aracılığıyla otomatik alınır, `GPG` (AES256) ile şifrelenir ve AWS S3 bucket'ına yüklenir.

---

## 2. Felaket Senaryosu & Kurtarma Adımları (Restore)

Sistem çökmesi veya veri merkezi kaybı durumunda uygulanacak kurtarma planı:

### Adım 1: Felaket İlanı ve Servislerin Durdurulması
Production API servislerini durdurarak veri tutarsızlığını önleyin:
```bash
docker compose stop backend
```

### Adım 2: S3'ten Son Yedek Dosyasını İndirme
```bash
aws s3 cp s3://serenut-backups/backups/serenut_db_LATEST.dump.gpg ./backup.dump.gpg
```

### Adım 3: GPG Şifre Çözme (Decryption)
Yedeğin şifresini `BACKUP_PASSPHRASE` şifresiyle çözün:
```bash
gpg --batch --yes --passphrase "$BACKUP_PASSPHRASE" --decrypt backup.dump.gpg > backup.dump
```

### Adım 4: Veri Tabanını Temizleme ve Geri Yükleme (Restore)
PostgreSQL üzerine yedeği geri yükleyin:
```bash
pg_restore --clean --no-owner -h localhost -U postgres -d postgres backup.dump
```

### Adım 5: Servisleri Başlatma ve Sağlık Kontrolü
```bash
docker compose up -d backend
curl -f http://localhost:3000/health
```

---

## 3. Fire Drill Test Geçmişi

| Tarih | Test Eden | Süre | Sonuç | Notlar |
|-------|-----------|------|-------|--------|
| 2026-07-06 | Antigravity AI | 5 dakika | ✅ BAŞARILI | Automated DR restore validation passed. |
