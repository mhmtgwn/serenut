# Serenut WhatsApp Business bildirim kanalı

Bu entegrasyon sohbet kutusu değildir. Şirket sahibi kendi WhatsApp Business
hesabını müşteri portalından bir kez bağlar; Serenut satış, tahsilat ve sipariş
olaylarını onaylı Meta şablonlarıyla müşteriye bildirir.

## Meta hazırlığı

Mevcut Meta varlıkları (gizli değildir):

- Uygulama: `Serenut Notifications`
- App ID: `1224880033182854`
- Business Portfolio: `Serenut` / yasal işletme `Nutopian Fındık İşleme Merkezi`
- Embedded Signup configuration: `Serenut Embedded Signup`
- Configuration ID: `2051947882108806`
- JavaScript SDK allowlist: `https://serenut.com`
- Webhook: `https://serenut.com/api/v1/whatsapp/webhook`

1. Serenut Meta Business hesabını doğrulayın ve Tech Provider sürecini tamamlayın.
2. Meta Developer uygulamasına WhatsApp ürününü ekleyin.
3. Embedded Signup configuration oluşturun.
4. Üretim callback domainini Meta uygulamasına ekleyin.
5. Webhook adresini `https://API_HOST/api/v1/whatsapp/webhook` olarak tanımlayın.
6. Webhook verify token değerini sunucudaki `WHATSAPP_WEBHOOK_VERIFY_TOKEN` ile aynı yapın.
7. `messages` ve `message_template_status_update` webhook alanlarına abone olun.
8. `business_management`, `whatsapp_business_management` ve
   `whatsapp_business_messaging` izinleri için gerekli üretim erişimlerini alın.

Meta Business Verification 13 Ağustos 2026 tarihinde gönderildi. Onay
gelene kadar uygulama geliştirme modunda kalmalı ve
`NOTIFICATION_ENABLED_CHANNELS` değerine `whatsapp` eklenmemelidir.

## App Review kanıt paketi

İnceleme videosunda tek ve kesintisiz akış gösterin:

1. Serenut müşteri portalında firma sahibiyle giriş yapın.
2. **Bildirim Kanalları → WhatsApp Business'ı Bağla** düğmesini açın.
3. Meta Embedded Signup içinde test işletmesini ve test numarasını seçin.
4. Bağlantı tamamlandığında WABA adı ile telefonun portalda göründüğünü gösterin.
5. Standart şablonları senkronize edin ve Meta tarafından onaylı bir şablon seçin.
6. Test bildirimi gönderip WhatsApp teslimini gösterin.
7. Meta tarafında mesaj şablonu listeleme/yönetme ekranını gösterin.

İnceleme açıklamasında Serenut'un serbest metin sohbet aracı olmadığı; her
müşterinin yalnız kendi WhatsApp Business hesabını bağladığı ve Serenut'un
satış, tahsilat ve sipariş olaylarını onaylı `UTILITY` şablonlarıyla gönderdiği
belirtilmelidir. Test kullanıcısı, test işletmesi ve numara yalnız Meta
inceleme formunun gizli test bilgileri alanında paylaşılmalıdır.

## Sunucu sırları

`server/.env.example` içindeki WhatsApp değişkenlerini secret manager üzerinden
tanımlayın. `META_APP_SECRET`, webhook verify token ve credential encryption key
Git'e yazılmamalıdır. `WHATSAPP_CREDENTIAL_ENCRYPTION_KEY` üretime çıktıktan
sonra plansız değiştirilmemelidir; mevcut müşteri tokenları bu anahtarla AES-256-GCM
şifrelenir.

VPS üzerinde Meta App Secret'i standart girdiden vererek diğer değerleri güvenli
biçimde üretin (komut çıktısı sırları göstermez):

```sh
printf '%s' "$META_APP_SECRET" | sh server/scripts/configure_whatsapp_env.sh
```

Meta Business Verification ve App Review tamamlandıktan sonra, canlı webhook
doğrulamasını geçmeden kanalı açmayan korumalı komutu çalıştırın:

```sh
sh server/scripts/enable_whatsapp_after_approval.sh
```

WhatsApp'ı yalnız tüm Meta ayarları tamamlandıktan sonra etkinleştirin:

```env
NOTIFICATION_ENABLED_CHANNELS=sms,email,whatsapp
```

## Yayına alma

1. `schema_v90.sql` migration'ını ayrı migration rolüyle uygulayın.
2. Backend'i yeni environment değerleriyle yayınlayın.
3. Portalda bir iç test firmasıyla Embedded Signup akışını tamamlayın.
4. Oluşturulan standart şablonların Meta durumunu portalda yenileyin.
5. En az bir şablon `approved` olduktan sonra test bildirimi gönderin.
6. `accepted`, `sent`, `delivered`, `read` ve `failed` webhook durumlarını
   `notification_queue` üzerinde doğrulayın.
7. Önce pilot firmalarda, ardından kademeli olarak üretimde açın.

## Güvenli davranış

- Bağlantı veya onaylı şablon yoksa WhatsApp olayı güvenli biçimde atlanır;
  mevcut yerel SIM SMS akışı çalışmaya devam eder.
- Ağ kesintisinde Android/Windows kaynaklı WhatsApp olayları yerel dayanıklı
  outbox'ta tutulur ve aynı `client_event_id` ile yeniden gönderilir.
- Worker, Meta mesaj kimliğini kaydeder; tekrar çalışan iş kabul edilmiş mesajı
  yeniden göndermemeye çalışır.
- Meta token hatası bağlantıyı `reauthorization_required` durumuna geçirir.
- Bağlantı kaldırılırken WABA webhook aboneliği kaldırılmaya çalışılır ve saklanan
  token kullanılamaz bir şifreli tombstone ile değiştirilir.

## Standart olaylar

- `sale_created`
- `debt_created`
- `collection_recorded`
- `order_created`
- `order_preparing`
- `order_ready`
- `order_delivered`
- `order_cancelled`

Serbest metin WhatsApp bildirimi gönderilmez. Her olay yalnız kendi onaylı Meta
şablonu ve sıralı parametreleriyle gönderilir.
