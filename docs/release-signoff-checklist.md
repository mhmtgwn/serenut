# Serenut istemci sürümü yayın onayı

Bu form her Android/Windows sürümünde doldurulur. Boş madde varsa sürüm
**yayınlandı** olarak duyurulamaz.

## Aday sürüm

- Sürüm/build: `________________`
- Git commit: `________________`
- GitHub Actions run: `________________`
- Testi yapan kişi ve tarih: `________________`

## Yayın öncesi zorunlu kontroller

- [ ] Sürüm ve build numarası daha önce kullanılmadı.
- [ ] `release-key-continuity` geçti.
- [ ] Android sertifika SHA-256 değeri policy ile aynı.
- [ ] OTA RSA imzalayanı policy içindeki aktif imzalayanla aynı.
- [ ] En eski doğrudan desteklenen `1.3.10+91` istemcisi aktif imzalayanı tanıyor.
- [ ] `1.2.1+60` veya daha eski cihazlar doğrudan OTA kitlesine alınmadı;
      eski anahtarla imzalanmış köprü sürüm planı uygulandı.
- [ ] Android ve Windows paketleri aynı CI run'ından üretildi.
- [ ] Android APK ve Windows EXE hash, boyut ve RSA doğrulaması geçti.

## Gerçek cihaz yükseltme testi

- [ ] Üretim imzalı eski sürüm Android test cihazına kuruldu.
- [ ] Uygulama içinden aday sürüm indirildi; SHA/RSA kontrolü geçti.
- [ ] Android “Bu kaynaktan yükleme” izni akışı denendi.
- [ ] APK mevcut uygulamanın üzerine veri silmeden kuruldu.
- [ ] Uygulama açıldı ve sürüm numarası doğrulandı.
- [ ] Üretim imzalı eski Windows sürümünden güncelleme bildirimi görüldü.
- [ ] Windows kurucusu çalıştı, uygulama açıldı ve sürüm doğrulandı.

## Canlı yayın sonrası

- [ ] Production job tamamen yeşil.
- [ ] Public Android ve Windows URL'leri HTTP 200 dönüyor.
- [ ] `node scripts/verify_published_release.js <sürüm+build>` geçti.
- [ ] En az bir gerçek Android ve Windows cihaz canlı pakete yükseltildi.
- [ ] Ancak bütün maddeler tamamlandıktan sonra müşterilere duyuru yapıldı.

## Hata sınıflandırması

- **“Dosya bütünlüğü veya dijital imza doğrulanamadı”**: OTA RSA anahtarı,
  hash veya indirilen dosya uyuşmuyor. APK sertifikasıyla ilgili değildir.
- **Android “Uygulama yüklenmedi / paket mevcut uygulamayla çakışıyor”**:
  Android APK sertifikası veya application ID uyuşmuyor.
- **“Bu kaynaktan uygulama yükleme”**: Android sistem izni kapalıdır; imza
  hatası değildir.
- Çok eski istemci yalnız eski OTA anahtarını tanıyorsa yeni anahtarlı paketi
  doğrudan kabul etmez. Önce eski anahtarla imzalanmış köprü sürüm gerekir.
