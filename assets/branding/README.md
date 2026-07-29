# Serenut logo paketi

Bu paket, verilen marka kılavuzundaki geometrik amblem ve renk kodları esas
alınarak yeniden çizilmiştir.

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

## Kullanım kuralları

- Amblemin çevresinde en az kendi ana çubuk kalınlığı kadar boşluk bırakın.
- Renkli sürümü beyaz veya çok açık nötr zeminde kullanın.
- Koyu/yeşil zeminde beyaz ters sürümü kullanın.
- Şekli döndürmeyin, oranlarını bozmayın, gölge veya efekt eklemeyin.
- Dijitalde 24 px altına inmeyin; baskıda minimum 8 mm kullanın.
- Android/PWA maskable ikonlarında `web/icon-maskable-*` dosyalarını tercih edin.

## Yeniden üretim

Kök dizinde:

```powershell
python tool/generate_brand_assets.py
```
