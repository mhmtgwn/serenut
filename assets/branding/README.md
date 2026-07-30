# Serenut logo paketi

Bu paket, onaylı Serenut görsellerinden platformlara uygun çıktılar üretir.

## Onaylı ana kaynaklar

- `source/app-icon-white.png`: Kullanıcı tarafından onaylanan geometrik işaretin referans kaynağıdır.
- `source/mark-transparent-effects.png`: Efektli transparan sunum görselidir. Küçük ikonlarda, giriş formlarında ve baskıda kullanılmaz.

## Ana renkler

- Yeşil: `#1B6B3C` — RGB `27, 107, 60`
- Sarı: `#E6B134` — RGB `230, 177, 52`
- Siyah: `#111111`
- Beyaz: `#FFFFFF`

## Klasörler

- `svg/`: Sonsuz ölçeklenebilir ana kaynaklar.
- `svg/serenut-*.svg`: “Serenut” yatay logoları.
- `svg/serenut-os-*.svg`: “Serenut OS” yatay logoları.
- `lockups/`: İki yazılı logonun renkli ve beyaz PNG çıktıları.
- `png/`: Şeffaf zeminli renkli ve tek renk çıktılar.
- `app/`: Açık ve yeşil zeminli yuvarlatılmış uygulama ikonları.
- `web/`: Favicon, standart PWA, maskable PWA ve sosyal paylaşım çıktısı.
- `windows/`: Çok çözünürlüklü Windows `.ico` dosyası.

## Ürün içindeki kullanım

- Android/iOS uygulama ikonları: platformun kendi maskesi üzerinde beyaz zemin ve çerçevesiz işaret.
- Windows uygulama ikonu: transparan zeminde çerçevesiz renkli işaret.
- Tarayıcı sekmesi: kutusuz, transparan ve boşluksuz sade renkli amblem.
- Giriş, kayıt ve şifre ekranları: yatay renkli `Serenut OS` logosu.
- Koyu panel kenar çubuğu: renkli amblem ve beyaz yazılı tek yatay logo.
- Açık web yüzeyleri: yatay renkli Serenut logosu.
- Fiş/baskı: efektsiz, yüksek kontrastlı yatay logo.

`assets/logo.png` Flutter ve fiş iş akışlarının ortak yatay logosudur. Eski
`assets/serenutoslogo.png` kopyası kullanılmadığı için kaldırılmıştır.

## Kullanım kuralları

- Amblemin çevresinde en az kendi ana çubuk kalınlığı kadar boşluk bırakın.
- Renkli sürümü beyaz veya çok açık nötr zeminde kullanın.
- Koyu/yeşil zeminde beyaz ters sürümü kullanın.
- Şekli döndürmeyin, oranlarını bozmayın, gölge veya efekt eklemeyin.
- İşareti ikinci bir yuvarlatılmış kart veya dekoratif çerçeve içine almayın.
- Dijitalde 24 px altına inmeyin; baskıda minimum 8 mm kullanın.
- Android/PWA maskable ikonlarında `web/icon-maskable-*` dosyalarını tercih edin.

## Yeniden üretim

Kök dizinde:

```powershell
python tool/generate_brand_assets.py
```
