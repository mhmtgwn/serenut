# Serenut OS — Geliştirici & Ajan Kuralları (AGENTS.md)

## 🚨 Önemli Mimari Kararlar & Kurallar

### 1. SQLCipher Kaldırılması (Veritabanı Kuralları)
* **SQLCipher Kullanımı Tamamen İptal Edilmiştir**: Mobil (Android) ve masaüstü (Windows) istemcilerinde şifreli veritabanı motoru olan `sqflite_sqlcipher` kullanımı tamamen kaldırılmıştır.
* **Standart SQLite**: İstemci tarafında veritabanı olarak standart, şifresiz `sqflite` kullanılmalıdır. Yeni eklenecek olan tüm yerel veritabanı sorguları ve bağlantıları standart SQLite formatına uygun olmalıdır.
* **Sunucu / VPS Veritabanı**: Backend/VPS tarafında ana veritabanı olarak PostgreSQL kullanılmaktadır. İstemciler ile VPS arasındaki veri senkronizasyonu HTTPS/REST API ve WebSocket kanalları üzerinden şifresiz yerel veriler ile şifreli sunucu verileri arasında köprü kurarak sağlanır.

### 2. Sürüm ve İndirme Dosyası Naming Standartları (Professional Versioning Rule)
* **`+` İletimi Yasaktır (Dosya Adları & Public UI)**: Kullanıcılara sunulan indirme dosyalarının isimlerinde (APK, EXE vb.), web sitesindeki indirme butonlarında ve genel arayüzde `+` içeren dahili Flutter build numaraları (ör. `1.2.3+65`) KULLANILAMAZ.
* **Profesyonel Format**:
  - Görünen ve İndirilen Dosya Adı: `SerenutOS-v1.2.3.exe` / `SerenutOS-v1.2.3.apk` (veya ihtiyaç halinde dahili build numarası gerekirse nokta kullanılarak `SerenutOS-v1.2.3.65.exe`).
  - Arka Plan / Sistem: `pubspec.yaml` içerisindeki `+65` yapısı sadece Flutter ve Android `versionCode` derlemesi için dahili olarak kullanılır; yayınlama betikleri (publish script) ve indirme controller'ları bunu otomatik temizleyip semantik formata (`v1.2.3` / `1.2.3`) çevirir.

