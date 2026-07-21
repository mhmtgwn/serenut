# Serenut OS Donanım Entegrasyon Planı

Bu plan canlı terazi, fiziksel kart POS ve fiş yazıcısı entegrasyonlarını aynı
genişletilebilir Windows donanım katmanı altında toplar. İlk hedef, sahada marka
ve model bilinmediğinde cihazı teşhis edebilmek ve desteklenen bir protokol varsa
satışı güvenle tamamlamaktır.

## Temel kararlar

- Donanımın ana sahibi Windows uygulaması/yerel donanım servisidir.
- Android ve iOS, Windows köprüsüne yerel ağ üzerinden bağlanır; doğrudan seri
  port veya Windows yazıcısına erişmez.
- Marka/model bağımlılıkları adaptörlerde kalır. Satış ekranı yalnızca ortak
  terazi, ödeme terminali ve yazıcı sözleşmelerini kullanır.
- Donanım bağlantısı sürekli açık olabilir fakat ölçüm veya ödeme yalnızca aktif
  bir satış oturumu içinde tüketilir.
- Para kuruş, canlı ağırlık gram cinsinden tam sayı olarak işlenir.
- Terminalden başarı alınmadan kartlı satış tamamlanmış sayılmaz.
- Yazdırma başarısızlığı ödemeyi veya satış kaydını geri almaz; çıktı kalıcı
  kuyruğa alınır.

## Ortak mimari

```text
Terazi (COM/USB/Ethernet) ----\
Fiziksel POS (LAN/COM/SDK) ---- Windows Hardware Hub ---- Flutter satış akışı
Yazıcı (Spooler/TCP/BT) -------/          |
                                          +---- LAN API / WebSocket
                                                Android ve iOS
```

`Hardware Hub` aşağıdaki sorumluluklara sahiptir:

- cihaz keşfi ve kullanıcı tarafından cihaz seçimi;
- bağlantı sağlığı ve son hata bilgisi;
- ham veri kaydı ve dışa aktarılabilir teşhis raporu;
- seçilen cihaz/protokol profilini kalıcı saklama;
- cihaz olaylarını normalize ederek uygulamaya yayınlama;
- bağlantı koptuğunda kontrollü yeniden bağlanma.

## 1. Canlı terazi

### Ürün modeli

Her üründe bir satış tipi bulunur:

- `piece`: adetle satış, mevcut davranış;
- `weighed`: canlı terazi ile kilogram üzerinden satış.

Ek alanlar:

- `sale_type` (`piece` varsayılan);
- `minimum_weight_grams` (varsayılan 20);
- `tare_grams` (varsayılan 0, ilk sürümde tercihen cihaz darası kullanılır).

Eski ürünler migrasyonda otomatik olarak `piece` kabul edilir. Ürün oluşturma ve
düzenleme ekranında "Adet" / "Tartılı (kg)" seçimi gösterilir.

### Veri modeli

Terazi adaptörü aşağıdaki normalize edilmiş ölçümü üretir:

```text
ScaleReading
  deviceId
  sequence
  grossGrams
  tareGrams
  netGrams
  stable
  overload
  measuredAt
  rawFrame (yalnız teşhis için)
```

Ham ölçüm satışa doğrudan eklenmez. `ScaleSession` son okumaları izler ve şu
koşullarda ağırlığı kabul eder:

- aktif tartılı ürün vardır;
- cihaz bağlıdır ve ölçüm günceldir;
- değer minimum ağırlığın üzerindedir;
- cihazın stabil bayrağı vardır veya son ölçümler tolerans içinde sabittir;
- ölçüm daha önce sepete eklenmemiştir;
- yeni tartım öncesinde terazi sıfıra dönmüştür.

### Kullanıcı akışı

1. Kasiyer tartılı ürünü seçer.
2. Tartım penceresi açılır ve canlı değer gösterilir.
3. Stabil değer için ürün, kg fiyatı ve toplam önizlenir.
4. Kasiyer `Sepete Ekle` ile onaylar.
5. Sepete gram ve gösterim için kilogram miktarı kaydedilir.
6. Terazi boşalmadan aynı ölçüm ikinci kez kullanılamaz.

İlk sürümde onay zorunludur. Otomatik ekleme daha sonra işletme ayarı olarak
eklenebilir.

### İlk adaptörler

- `SimulatedScaleAdapter`: donanım olmadan geliştirme/test;
- `SerialScaleAdapter`: Windows COM port, ayarlanabilir baud/parity/data/stop;
- profil tabanlı metin ayrıştırıcı: sürekli yayın ve sorgu-cevap modu;
- `NetworkScaleAdapter`: sonraki aşamada TCP terazi.

Teşhis ekranı portları listeler, ham çerçeveleri gösterir ve kullanıcıya çalışan
ayarları profil olarak kaydetme imkanı verir.

## 2. Fiziksel kart POS

### Ödeme ilkesi

Kart düğmesi artık doğrudan satış oluşturmaz. Akış:

```text
Sepet hazır
  -> ödeme isteği ve idempotency key oluştur
  -> terminale tutarı gönder
  -> terminal sonucu bekle
  -> başarılıysa satış + ledger kaydını atomik tamamla
  -> başarısız/iptalse satış oluşturma
  -> sonuç belirsizse UNRECONCILED olarak inceleme kuyruğuna al
```

Mevcut `PaymentFSM` genişletilerek şu durumlar açıkça ele alınır:

- idle;
- initiated;
- terminalSent;
- authorized;
- declined;
- cancelled;
- timeout;
- completed;
- unreconciled.

### Ortak terminal sözleşmesi

Her üretici adaptörü şunları sağlar:

- bağlantı/sağlık kontrolü;
- satış başlatma;
- aktif işlemi iptal etme;
- işlem durumunu sorgulama;
- iptal/iade;
- gün sonu veya mutabakat bilgisi (cihaz destekliyorsa).

Kart numarası, CVV veya PIN uygulamaya alınmaz ve loglanmaz. Yalnızca güvenli
işlem referansı, provizyon kodu, terminal kimliği, tutar ve sonuç saklanır.

### İlk adaptörler

- `SimulatedPaymentTerminal`: başarılı, red, timeout ve belirsiz sonuç testleri;
- `ManualPaymentTerminal`: cihaz entegrasyonu yoksa kasiyer terminal sonucunu
  açıkça doğrular; otomatik entegrasyon gibi gösterilmez;
- `HuginPcLinkAdapter`: resmi erişim/aktivasyon bilgileri sağlandığında ilk gerçek
  ağ adaptörü;
- diğer üreticiler aynı sözleşmeye eklenir.

Karma ödemede yalnız kart payı terminale gönderilir. Terminal kart payını
onaylamadan nakit/borç bileşenleriyle satış tamamlanmaz.

## 3. Yazıcı keşfi ve teşhisi

### Destek yolları

- Sunmi gömülü yazıcı;
- Windows Spooler üzerinden RAW çıktı;
- ağ yazıcısı için ESC/POS TCP (öncelikle 9100);
- Android eşleşmiş Bluetooth Classic yazıcı;
- manuel yazıcı adı, IP/port veya MAC girişi.

### Keşif

- Windows'ta kurulu yazıcılar listelenir ve varsayılan yazıcı işaretlenir.
- Yerel IPv4 ağında sınırlandırılmış, paralel TCP port taraması yapılır.
- Ağ taraması yalnız kullanıcının başlatmasıyla çalışır ve iptal edilebilir.
- Bir portun açık olması "yazıcı doğrulandı" anlamına gelmez; aday olarak
  gösterilir ve kullanıcı ayrı test çıktısı gönderir.
- Android 12+ Bluetooth izinleri çalışma zamanında istenir.
- Bluetooth keşfi başarısızsa işletim sistemi ayarlarında eşleştirme ve manuel
  MAC seçeneği korunur.

### Teşhis çıktısı

Test sayfası sırayla şunları sınar:

- Türkçe karakterler;
- 58/80 mm satır genişliği;
- kalın/büyük metin;
- QR ve barkod;
- logo/raster görsel;
- kesici ve çekmece komutu (ayrı, kullanıcı onaylı test).

Kesici ve çekmece komutları varsayılan testte gönderilmez; desteklemeyen cihazda
istenmeyen davranış oluşturmasını önlemek için ayrı düğmelerdir.

## Uygulama sırası

### Faz A — Güvenli çekirdek

1. Donanım durum, hata ve teşhis modelleri.
2. Terazi okuma/oturum sözleşmeleri ve simülatör.
3. Ödeme terminali sözleşmesi, FSM genişletmesi ve simülatör.
4. Yazıcı keşif sözleşmesi ve simülatör.
5. Birim testleri: stabilite, çift tartım, çift çekim, timeout ve tekrar deneme.

### Faz B — Ürün ve satış entegrasyonu

1. Veritabanı migrasyonu ve ürün satış tipi.
2. Ürün formunda Adet / Tartılı (kg) seçimi.
3. Sepette adet ile gramın güvenli temsili.
4. Canlı tartım penceresi.
5. Kart ödeme orkestrasyonunun satış oluşturma noktasına bağlanması.

### Faz C — Windows saha desteği

1. COM port listeleme ve seri terazi adaptörü.
2. Windows kurulu yazıcı listeleme ve RAW test.
3. Sınırlandırılmış ağ yazıcısı keşfi.
4. Donanım merkezi ayar/teşhis ekranı.
5. Dışa aktarılabilir JSON ve metin teşhis raporu.

### Faz D — Mobil ağ istemcisi

1. Windows köprüsünde kimlik doğrulamalı yerel API/WebSocket.
2. Cihaz eşleştirme ve kısa ömürlü erişim anahtarı.
3. Android/iOS canlı ağırlık izleme ve ödeme komutu.
4. Bağlantı kopması ve eski ölçüm korumaları.

## Kabul kriterleri

### Terazi

- Adet ürünü tartım penceresi açmadan sepete girer.
- Tartılı ürün stabil ölçüm olmadan sepete eklenemez.
- Aynı ölçüm iki kez kullanılamaz.
- Bağlantı kopması açık ve anlaşılır hata üretir.
- Simülatörle kararsız, stabil, negatif ve aşırı yük senaryoları test edilir.

### Kart POS

- Terminal onayı olmadan kartlı satış tamamlanmaz.
- Aynı idempotency key ile ikinci çekim başlatılmaz.
- Red ve kullanıcı iptalinde stok/satış/ledger değişmez.
- Belirsiz sonuç yeni çekim başlatmak yerine mutabakat kuyruğuna gider.

### Yazıcı

- Windows kurulu yazıcıları listeler.
- Ağ adaylarını bulur veya manuel IP kabul eder.
- Test çıktısı ile bağlantı sonucu birbirinden ayrılır.
- Başarısız çıktı kalıcı kuyrukta korunur.
- Kullanıcı yanlış cihaza otomatik failover konusunda uyarılır; seçilmemiş bir
  yazıcıya sessizce çıktı gönderilmez.

## Yarınki saha kontrol listesi

- Windows sürümü, uygulama sürümü ve ağ arayüzlerini kaydet.
- Terazi marka/modeli, bağlantı tipi, COM ayarları ve örnek ham veriyi kaydet.
- Boş, stabil, hareketli ve dara uygulanmış ölçüm örnekleri al.
- POS marka/model, banka, bağlantı tipi ve üretici entegrasyon yetkisini kaydet.
- Windows yazıcı adını, sürücüsünü, bağlantı yolunu ve kağıt genişliğini kaydet.
- 9100 port erişimi ve Windows test sayfasını ayrı ayrı doğrula.
- Türkçe karakter, kesici, çekmece ve logo sonuçlarını teşhis raporuna ekle.

