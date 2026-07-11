# Incident Management & Alert Routing Runbook

**Serenut OS — Versiyon 1.0 | Son Güncelleme: 2026-07**

---

## 1. Olay Dereceleri (Incident Severity)

Platformda oluşan olaylar (incident) kritiklik derecelerine göre 4 kategoriye ayrılır:

| Severity | Tanım | Yanıt Süresi (SLA) | Çözüm Süresi (SLA) |
|----------|-------|---------------------|--------------------|
| **SEV-1 (Critical)** | Sistem tamamen devre dışı, servis kesintisi var. | 15 Dakika | 4 Saat |
| **SEV-2 (High)** | Ana işlevlerden biri (örn. Billing, Sync) bozuk. | 1 Saat | 24 Saat |
| **SEV-3 (Medium)** | Sistem çalışıyor fakat performans düşüşü veya kısmi hata var. | 24 Saat | 72 Saat |
| **SEV-4 (Low)** | Küçük hatalar, kozmetik veya UX iyileştirmeleri. | Next Sprint | Next Release |

---

## 2. Alarm Yönlendirme Matrisi (Alert Routing)

Kritiklik derecelerine göre alarm dağıtım kanalları:

```
[Incident Oluştu]
       │
       ├─► SEV-1 ──► Discord/Slack Webhook + Admin SMS (Netgsm) + Critical Log
       ├─► SEV-2 ──► Discord/Slack Webhook + Admin SMS + Admin Email (Postmark)
       ├─► SEV-3 ──► Admin Email (Postmark)
       └─► SEV-4 ──► Discord/Slack Webhook / Winston Log
```

---

## 3. Bakım Pencereleri (Maintenance Windows)

Planlı bakım çalışmaları için takip edilecek adımlar:

1. **Önceden Bildirme:** En az 48 saat önceden kullanıcılara portal üzerinden duyuru gönderilir.
2. **Bakım Modunun Açılması:** Admin portalı üzerinden bakım modu aktif hale getirilir.
3. **Sağlık Kontrolü Tepkisi:** Bakım modunda `/health` endpoint'i `503 Service Unavailable` ve `{ status: "maintenance" }` döner.
4. **İşlem Sonu:** Çalışma tamamlandıktan sonra bakım modu kapatılır.
