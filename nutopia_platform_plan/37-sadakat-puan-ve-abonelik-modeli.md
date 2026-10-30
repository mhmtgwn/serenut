# 37 — Müşteri Sadakat, Puan Kazanımı ve Düzenli Ezme Abonelik Modeli (Subscription & Loyalty)

> Bu belge; Nutopiano müşterilerinin her alışverişte ve çiftçilerin her değirmen işletmesinde puan kazanmasını sağlayan **Sadakat/Puan Motorunu** ve sporcular/sağlıklı beslenenler için her ay otomatik kapıya gelen **Düzenli Fındık Ezmesi Abonelik Sistemini** belirler.
> Veri mimarisi: `14-sql-sema.md` içindeki `core.credit_entries` tablosu puan ve cüzdan bakiyelerini değişmez olarak yönetir.

---

## 1. FINDIK PUAN (SADAKAT PROGRAMI) KURALLARI

Müşterilerin devamlı alışveriş yapmasını ve çiftçilerin her sezon fındığını Nutopia Değirmeni'ne getirmesini teşvik eden puan mekanizması:

```mermaid
flowchart LR
    A["Alışveriş Yap (Mağaza)"] -->|Her 100 TL'ye 5 TL Puan (%5)| C[("Müşteri Fındık Puan Cüzdanı")]
    B["Değirmende Fındık Kırdır/Ez"] -->|Her 100 kg'a 100 TL İndirim Puanı| C
    C --> D["Sonraki Alışverişte İndirim Olarak Harca (1 Puan = 1 TL)"]
```

### 1.1 Puan Kazanım Oranları
1. **E-Ticaret Alışverişleri:**
   - Tamamlanan ve iade edilmeyen her siparişte harcanan tutarın **%5'i** puan olarak birikir (Örn: 500 TL alışveriş -> 25 TL Fındık Puan).
2. **Değirmen Hizmetleri (Çiftçi Sadakati):**
   - Değirmende işlenen her 100 kg kabuklu fındık için çiftçiye **100 TL Değirmen Puanı** yüklenir. Çiftçi bir sonraki gelişinde bu puanı işleme ücretinden düşebilir.
3. **Puan Harcama:**
   - Sepet adımında: `[X] 45,00 TL Fındık Puanımı Kullan`.
   - 1 Puan = 1,00 TL. Sepet tutarının en fazla %50'si puanla ödenebilir (Nakit akışı koruması).
   - Puanların geçerlilik süresi: **1 Yıl** (Kullanılmayan puanlar sezon sonunda nazik bir hatırlatma SMS'i ile bildirilir).

---

## 2. DÜZENLİ EZME ABONELİK MODELİ (SUBSCRIBE & SAVE)

Özellikle sporcular, diyet yapanlar ve çocuklu aileler her ay düzenli olarak %100 katkısız fındık ezmesi tüketir.

### 2.1 Abonelik Akışı
- **Ürün Sayfasında Seçenek:**
  - `(o) Tek Seferlik Satın Al: 195,00 ₺`
  - `(o) Abone Ol & %10 İndirim Kazan: 175,50 ₺ / Ay`
- **Abonelik Sıklığı:** `Her 30 Günde Bir` veya `Her 60 Günde Bir`.
- **Otomatik Kart Çekimi:** iyzico Saklı Kart (Card Tokenization) altyapısı ile her ay belirlenen günde tutar otomatik çekilir, sipariş hazırlanacaklar listesine düşer.
- **Koşulsuz İptal & Erteleme:** Müşteri dilediği an hesabından tek tıkla *"Bu ay tatile gidiyorum, siparişimi 1 ay ertele"* veya *"Aboneliğimi durdur"* diyebilir; müşteri hizmetlerine bağlanma zorunluluğu yoktur.

