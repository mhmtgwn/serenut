# 01 — Ürün ve Kapsam

## 1. Personalar
| Persona | Tanım | Ana ihtiyaç | Cihaz |
|---|---|---|---|
| **Ayşe** (alıcı) | Büyükşehirde, kahvaltılık/sağlıklı ürün arayan | Güvenilir, katkısız ürün; hızlı, güvenli ödeme; kargo takibi | Mobil %80 |
| **Hasan** (çiftçi) | Ereğli/Zonguldak çevresinde fındık bahçesi sahibi, 40–60 yaş | Fındığı taşımadan işletmek; net fiyat; telefonla/SMS ile işlem | Mobil, düşük teknik |
| **Kurumsal alıcı** | Otel, kafe, hediye alıcısı | Toptan fiyat, fatura, teklif | Masaüstü |
| **İşletme sahibi** | Siz | Tek ekranda sipariş, talep, stok, para | Masaüstü+mobil |
| **Paketleme personeli** | Depo | Hazırlanacak siparişler, etiket | Tablet/mobil |
| **Şoför** | Kurye | Günün alım listesi, adres, tartı girişi | Mobil, eldivenli/dışarıda |

## 2. Kullanıcı hikâyeleri (öncelik: M=Must, S=Should, C=Could)

### Mağaza
| ID | Hikâye | Ö |
|---|---|---|
| MAG-01 | Ürünleri kategori/arama/filtre ile gezerim | M |
| MAG-02 | Ürün sayfasında gramaj seçer, fiyat/stok/besin/alerjen görürüm | M |
| MAG-03 | Sepete ekler, adet değiştirir, kupon uygularım | M |
| MAG-04 | Misafir olarak adres girer ve ödeme yaparım | M |
| MAG-05 | Kartla (3D Secure), havale/EFT ile veya kapıda öderim | M |
| MAG-06 | Sipariş özeti e-posta/SMS alırım, durumu takip linkiyle izlerim | M |
| MAG-07 | Kargo takip numarasını görürüm | M |
| MAG-08 | Hesap açarsam geçmiş siparişlerimi ve adreslerimi görürüm | S |
| MAG-09 | Ürün yorumu/puanı bırakırım (satın alanlar) | C |
| MAG-10 | Stokta yoksa "haber ver" bırakırım | C |
| MAG-11 | Hediye notu ve hediye paketi seçerim | S |
| MAG-12 | Şehit yakını/gazi indirimini belgeyle talep ederim | S |
| MAG-13 | Kurumsal teklif talep ederim | C |

### Değirmen & Kurye
| ID | Hikâye | Ö |
|---|---|---|
| DEG-01 | Fiyat listesini görür, hesaplayıcıyla tahmini ücret bulurum | M |
| DEG-02 | Telefon+SMS koduyla giriş yapar, bahçe adresimi pinleyerek talep açarım | M |
| DEG-03 | Tahmini kg, hizmet (kırma/kavurma/ezme/paket) ve uygun günü seçerim | M |
| DEG-04 | Talebimin onay/planlanma durumunu SMS ve ekrandan görürüm | M |
| DEG-05 | Şoför gelince alım kodunu söyler, tartı sonucunu ve fişi görürüm | M |
| DEG-06 | İşlemim hazır olunca haber alır, teslim ya da gelip alma seçerim | M |
| DEG-07 | Kesin ücreti görür, kapıda veya çevrimiçi öderim | M |
| DEG-08 | Geçmiş taleplerimi ve randıman bilgilerimi görürüm | S |
| DEG-09 | Kapsama dışı adreste uyarılırım, bekleme listesine yazılırım | S |
| DEG-10 | Kendim getiriyorsam randevu alırım (kurye yok) | S |

### Yönetim
| ID | Hikâye | Ö |
|---|---|---|
| ADM-01 | Ürün/varyant/görsel/fiyat/stok eklerim, taslak-yayında yönetirim | M |
| ADM-02 | Siparişleri listeler, durum değiştirir, paketleme fişi/kargo etiketi alırım | M |
| ADM-03 | Havale ödemesini manuel onaylarım | M |
| ADM-04 | İade/iptal yaparım, kısmi iade veririm | M |
| ADM-05 | Değirmen taleplerini onaylar, ücret tahmini belirler, gün/şoför atarım | M |
| ADM-06 | Şoför listesi ve günlük rota planı görürüm | M |
| ADM-07 | Tartı/randıman/parti kayıtlarını denetlerim | M |
| ADM-08 | Fiyat listesi, kargo kuralı, kapsama bölgesi, kupon yönetirim | M |
| ADM-09 | Günlük ciro, sipariş, stok, bekleyen talep özetini görürüm | S |
| ADM-10 | Personel hesapları ve yetkileri yönetirim | M |
| ADM-11 | Müşteri/KVKK taleplerini (silme, dışa aktarım) yürütürüm | S |
| ADM-12 | Muhasebeye CSV/Excel dışa aktarım | S |

### Şoför
| ID | Hikâye | Ö |
|---|---|---|
| SOF-01 | Günün alım listesini sırayla görürüm | M |
| SOF-02 | Adrese yol tarifi açar, müşteriyi ararım | M |
| SOF-03 | Alım kodunu doğrular, brüt/dara/net kg girer, fotoğraf eklerim | M |
| SOF-04 | Alımı tamamlar/erteler/iptal eder, nedeni yazarım | M |
| SOF-05 | Konum paylaşımı (isteğe bağlı, rıza ile) | C |
| SOF-06 | Teslim turunda tutar tahsil edildi (nakit/kart) işaretlerim | S |

## 3. Kapsam sınırları
**MVP (yayına çıkış):** MAG-01…07, 11 (kısmen), DEG-01…07, ADM-01…08, ADM-10, SOF-01…04.
**v1.1:** hesaplar, kupon gelişmiş, raporlar, kargo otomasyonu, e-arşiv entegrasyonu.
**Sonra:** yorumlar, stok bildirimi, kurumsal teklif, çok dilli, mobil uygulama, rota optimizasyonu, abonelik (düzenli ezme).
**Kapsam dışı (şimdilik):** pazaryeri (Trendyol/Hepsiburada) entegrasyonu, çoklu depo, çoklu para birimi, yurt dışı kargo.

## 4. İş kuralları (başlangıç değerleri — hepsi yönetim ayarı olacak)
| Kural | Başlangıç | Not |
|---|---|---|
| Ücretsiz kargo eşiği | 750 ₺ (indirim sonrası, kargo hariç) | ayar |
| Havale indirimi | %5 | ayar; yalnız ürün tutarı |
| Gazi/şehit yakını indirimi | %20 | belge doğrulamayla, manuel onay; kupon kodu değil |
| Kupon | HOSGELDIN10 (%10), ilk sipariş | kullanım limiti, süre, min tutar |
| Kapıda ödeme | açık/kapalı, ek ücret alanı | yalnız belirli ürün/tutar altı olabilir |
| Stok rezervi | ödeme başlayınca 15 dk | süre dolunca iade |
| Değirmen min. miktar | yok | ayar (kg) |
| Değirmen kapsama | ilçe/mahalle listesi | ayar |
| Randıman tahmini | %50 | yalnızca bilgilendirme |
| Fiyat gösterimi | KDV dahil | KDV oranı ürün bazlı, muhasebeciyle doğrulanır |
| Teslimat süresi | sipariş 1–2 iş günü kargoya | ayar |

## 5. Başarı ölçütleri (KPI)
- Mağaza: dönüşüm oranı, sepet terk oranı, ortalama sipariş tutarı, tekrar alım.
- Değirmen: talep sayısı, talepten alıma süre, alımdan teslime süre, talep başına gelir, tekrar eden çiftçi oranı.
- Operasyon: yanlış/eksik sipariş oranı, ödeme hata oranı, destek mesajı sayısı.
- Teknik: LCP < 2,5 sn, uptime ≥ %99,5, ödeme webhook işleme başarı ≥ %99,9.

## 6. Değirmen–Mağaza çapraz fırsatlar (ileride)
- Ezme teslimi sırasında Nutopiano ürün önerisi, çiftçiye kupon.
- Sepete "değirmen hizmeti" ekleme (tek ödeme) — v2.
- Müşteri tabanı birleşik, ama modüller ayrı kalır (bkz. 02-mimari).

