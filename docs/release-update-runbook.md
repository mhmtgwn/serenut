# Serenut OS güvenli güncelleme kılavuzu

Bu belge Android ve Windows istemci güncellemelerinin tek desteklenen yayınlama
akışını tanımlar. `scripts/publish_v*.py`, elle yazılmış SQL ve dosyayı doğrudan
`openssl dgst -sign` ile imzalama yöntemleri eski/uyumsuz yöntemlerdir ve yeni
bir sürüm için kullanılmamalıdır.

## Değişmez imza sözleşmesi

Güncelleme bütünlüğü ile işletim sistemi paket imzası farklı katmanlardır:

1. APK, her sürümde aynı Android release keystore ile imzalanır. Beklenen
   sertifika SHA-256 parmak izi CI içinde doğrulanır.
2. EXE/kurulum dosyası Windows Authenticode sertifikasıyla imzalanır.
3. OTA doğrulaması için APK/EXE dosyasının küçük harfli 64 karakter SHA-256
   değeri hesaplanır. RSA-SHA256 imzasının girdisi dosyanın kendisi değil, bu
   hash değerinin UTF-8 metnidir.
4. Sunucudaki `sha256_hash`, `signature` ve `file_size_bytes` aynı, son
   artefakttan tek işlemde üretilir. Yayın aracı imzayı veritabanına yazmadan
   önce public key ile tekrar doğrular.
5. Yayınlanmış bir sürümün baytları değişmezdir. Aynı `version+build` ile farklı
   APK/EXE yayınlanamaz; her yeniden derlemede build numarası artırılır.
6. Uygulama güncellemeleri sürüme özel `/version/<version+build>` URL'sinden
   indirilir. Değişken `/latest` adresi yalnız web sitesindeki elle indirme
   bağlantılarıyla geriye uyumluluk içindir ve önbelleğe alınmaz.

## Her sürümde izlenecek akış

1. `pubspec.yaml` içindeki sürümü artırın: `MAJOR.MINOR.PATCH+BUILD`.
2. `config/signing_public_keys.json` içinde aktif release anahtarının
   `RELEASE_RSA_MODULI` listesinin ilk elemanı olduğunu kontrol edin. Bu
   virgül ayrımlı değer ile `RELEASE_RSA_TRUSTED_MODULI` dizisi aynı sıra ve
   içerikte olmalıdır; güvenli yerel derleme betiği farkı reddeder. Özel
   anahtarı repoya veya artefakta koymayın.
   `server/release-signing-policy.json` içindeki parmak izi, cihazlarda kurulu
   desteklenen sürümlerin güvendiği imzalayanı sabitler. Bu dosyayı sıradan bir
   sürümde değiştirmeyin.
3. Yerel kritik kontrolleri çalıştırın:

   ```powershell
   flutter test test/services/release_manager_test.dart
   Set-Location server
   npm run build
   npm run test:release-signing
   ```

4. Android/Windows artefaktlarını yalnızca `.github/workflows/deploy.yml`
   üzerinden üretin. Android release secret'ları eksikse yayın yapılmaz;
   debug anahtara geri dönüş yoktur.
   `release-key-continuity` işi yeni imzalayanı önceki istemci anahtar listesiyle
   karşılaştırır. Önceki istemcinin tanımadığı bir anahtar seçilirse tüm yayın
   artefakt yüklenmeden durur. VPS yayınlayıcısı ayrıca gerçek özel anahtarın
   policy parmak iziyle eşleşmesini zorunlu tutar ve bunu migration/container
   değişikliklerinden önce çalıştırır.
5. `main` dalındaki başarılı iş akışı artefaktları VPS'e yükler ve
   `server/scripts/deploy_production_ci.sh <sürüm+build>` komutunu çalıştırır.
   Bu betik, kanonik `dist/scripts/publish-release.js` yayınlayıcısını kullanır.
6. İşlem ancak `scripts/verify_published_release.js` Android ve Windows
   artefaktlarını public sürüme özel URL'lerden indirip şu kontrollerin tümünü
   geçerse başarılı sayılır: doğru sürüm, değişmez URL, dosya boyutu, SHA-256
   ve istemci trusted keyring'iyle RSA imzası. Bu kontrol production dağıtım
   betiğinin zorunlu son adımıdır; başarısızsa yayın başarılı kabul edilmez.
7. En az bir Android ve bir Windows test cihazında indirme ve kurulum yapın;
   ardından kademeli dağıtım gerekiyorsa rollout oranını yükseltin.

## Elle kurtarma yayını

Otomatik dağıtımın artefaktları ürettiği fakat yayın aşamasının kesildiği özel
durumlarda **Publish Prepared Client Artifacts** iş akışı elle çalıştırılabilir.
Başarılı kaynak `run_id` ve `pubspec.yaml` ile aynı tam sürüm girilmelidir. Bu
akış artık `main` push'larında otomatik çalışmaz ve sabit/eski bir sürümü tekrar
yayınlamaz.

## Anahtar rotasyonu

Release özel anahtarı değiştirilecekse istemci ve imzalayan aynı sürümde tek
adımda değiştirilmez. Ayrıntılı iki aşamalı prosedür için
[`signing-key-rotation.md`](signing-key-rotation.md) belgesini izleyin.

## Hata halinde

- `missing release signature`: Kanonik yayınlayıcı atlanmış veya VPS release
  secret'ı bağlanmamıştır. Yayını aktif etmeyin.
- `SHA-256 mismatch`: Veritabanına kaydedildikten sonra farklı bir dosya servis
  ediliyordur. Dosyayı yerinde değiştirmeyin. Yanlış yayını durdurun, build
  numarasını artırın ve kanonik akışla yeni bir sürüm yayınlayın.
- `RSA signature did not match`: İstemcideki trusted keyring ile VPS'teki
  release private key aynı anahtar ailesinde değildir. Anahtar rotasyonu
  prosedürünü uygulayın.
- Android paket imzası hatası: APK farklı keystore ile üretilmiştir. Mevcut
  uygulamanın üzerine kurulamaz; doğru production keystore ile yeniden üretin.
