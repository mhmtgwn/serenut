# Audit Log Retention Policy

**Serenut OS — Versiyon 1.0 | Son Güncelleme: 2026-07**

---

## Amaç

Bu politika, Serenut OS platform tarafından üretilen denetim (audit) loglarının saklanma sürelerini, arşivleme prosedürlerini ve GDPR uyumu kurallarını tanımlar.

---

## Depolama Katmanları

| Katman | Tablo | Süre | Açıklama |
|--------|-------|------|----------|
| **Hot Storage** | `audit_logs` | 1 yıl | Aktif sorgulama ve gerçek zamanlı erişim |
| **Cold Storage** | `audit_logs_archive` | 3 yıl | Tarihsel analiz ve yasal zorunluluk |
| **Purge** | — | 3 yıldan eski | Fiziksel silme (uyumluluk gerektirir) |

---

## Arşivleme Süreci

### Otomatik Arşivleme (Aylık Cron)
Her ayın ilk günü, `archive_old_audit_logs()` PostgreSQL fonksiyonu çalışır:
1. `audit_logs` tablosunda `created_at < NOW() - INTERVAL '1 year'` olan kayıtlar seçilir.
2. Bu kayıtlar `audit_logs_archive` tablosuna INSERT edilir.
3. Kaynak tablodaki kayıtlar silinir.

**Cron önerisi (VPS crontab):**
```cron
0 3 1 * * psql $DATABASE_URL -c "SELECT archive_old_audit_logs();" >> /var/log/serenut-audit-archive.log 2>&1
```

### Manuel Arşivleme (Admin Panel)
Admin paneli üzerinden `POST /api/v1/admin/audit-logs/archive` endpointi tetiklenebilir. Dönen `archivedCount` değeri kaç kaydın taşındığını gösterir.

---

## Purge (Temizleme) Süreci

3 yıldan eski arşiv kayıtları `purge_ancient_audit_archive()` fonksiyonu ile silinir:

```cron
0 4 1 1 * psql $DATABASE_URL -c "SELECT purge_ancient_audit_archive();" >> /var/log/serenut-audit-purge.log 2>&1
```

> [!CAUTION]
> Purge işlemi geri alınamaz. Yasal zorunluluk varsa (örn. GDPR ihlali soruşturması) purge zamanlaması dondurulmalıdır.

---

## CSV Export

Admin, `GET /api/v1/admin/audit-logs/export` endpointini kullanarak tarih aralığı belirterek audit loglarını CSV formatında dışa aktarabilir:

```
GET /api/v1/admin/audit-logs/export?from=2025-01-01&to=2025-12-31
```

**CSV içeriği:** `id, company_id, company_name, user_id, user_name, action, entity, entity_id, old_value, new_value, ip_address, created_at`

---

## INSERT-ONLY Politikası

`audit_logs` ve `audit_logs_archive` tabloları **INSERT-ONLY** prensibiyle yönetilir:
- Kayıtlar hiçbir zaman UPDATE edilmez.
- Silme işlemi yalnızca yasal arşivleme akışı kapsamında gerçekleşir.
- Admin panelinden tek tek kayıt silinemez (RLS politikası bunu engeller).

---

## GDPR Uyumu

GDPR `Unutulma Hakkı (Right to Erasure)` kapsamında kişisel veri talebi alındığında:
1. İlgili kullanıcıya ait audit log kayıtlarında `user_id` alanı `ANONYMIZED` ile güncellenir.
2. `old_value` ve `new_value` JSON alanlarındaki kişisel veriler kaldırılır.
3. Bu işlem ayrı bir `GDPR_ERASURE` audit logu olarak kaydedilir.

> [!IMPORTANT]
> GDPR erasure işlemi yalnızca yazılı talep ve yasal inceleme sonrasında uygulanır. Otomatik değil, manuel süreçtir.

---

## Sorumluluklar

| Rol | Sorumluluk |
|-----|------------|
| **Platform Admin** | Aylık arşivleme cron'unun çalıştığını doğrular |
| **DevOps** | Cron başarısız olduğunda email alert alır ve müdahale eder |
| **Hukuk/Uyum** | GDPR talebi geldiğinde Platform Admin'i bilgilendirir |

---

## Referanslar

- PostgreSQL fonksiyonları: `db/schema_v10.sql`
- Arşivleme endpoint: `POST /api/v1/admin/audit-logs/archive`
- Export endpoint: `GET /api/v1/admin/audit-logs/export`
