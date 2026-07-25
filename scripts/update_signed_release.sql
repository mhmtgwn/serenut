
DELETE FROM app_versions WHERE version_code IN ('1.1.9', '1.1.9+17', '1.1.9+18', '1.1.9+19', '1.1.9+20') AND channel = 'stable';

INSERT INTO app_versions (
  id, version_code, platform, channel, download_url, file_path,
  sha256_hash, signature, file_size_bytes, is_mandatory, min_required_version,
  release_notes, status, rollout_percentage, published_by
) VALUES
  ('rel-win-119-20', '1.1.9+20', 'windows', 'stable',
   '/api/v1/updates/download/windows/latest',
   '/var/www/serenut/server/public/website/downloads/SerenutOSSetup.exe',
   '4dd4c7b462651ee66f2529bb561a5b17417d32095220cf1908ad94362407503c', 'DxsPxl/kS+S/mgRlkGAmhgaUoLYN/y8C+W03E5cCgRh0EZ6haLWkqKJMgJMdAOB6LDwQoyk7nzZD5CSlexUAh636oDadAzDYDB5h1l/PPhFttLNMHDtp7gObahbbYcxnnvxOMVgaoJNfugwGF+NoK+bQz9pT4JwN05TRZgOEWAoEBhCTmIqRIvw0V148f26/fzTuO/XrK3OLmMKjAKBjfw0jc+XJgiTWtyrX9wSgrwDoua5FQ9cAEfrjyOqyH/1pjguL/5tHdqfndI6okX/DTwFxxyYNRQYWGwTsK501bXWgUFUJy+zOEdu5oS6UehwQcSDTMxqbuYQuUQfGg3rYuX8x5j/6cna7MdcB+i/Ovy2ayVv7yDQuzRpl5gIhxF0NRRDeI4UyUQAJw3gvo63s+olzn4F2T3jsSf5crZLICKerytT1nMtUf962hw/C7BLjM60Ya4CNsEqBIY1oNRS2uNu/Gu2FexygwlT5UBwfsDfBy/+PkRSSkrqxMZZ+CPgi', 40435256, false, '1.1.8',
   'Serenut OS v1.1.9+20 — Satış ve stok verilerinin tüm cihazlara toplu basılması ve anlık eşitlenmesi düzeltildi.',
   'active', 100, 'system'),
  ('rel-apk-119-20', '1.1.9+20', 'android', 'stable',
   '/api/v1/updates/download/android/latest',
   '/var/www/serenut/server/public/website/downloads/serenut.apk',
   '571b529ef7c5453c7f0aa6b8c2b6919e21abe4ab2d4a22c64ba6bd1c34d84841', 'JztjCvj/Wmw3U11yjRaULPHz5O93T2tcy+OfVqEBTggqUOIO5JwrN3ZCVgsx1fgmvWO6pJFWsiN/1o+cDmzUusjxmND3dPwBNrKU4LixQ2PF1lvS1wlkJgJLE0XWOaXck30auVxkDkrHHLzogJczoJywo1V4cR0HZqXNAt1oeyOdkM0VNZH6zKmTP70IqfMqVFGTaz0sPR0TzRmf7BpDCuRAZsYCbRbaOQd8aREOgJq/j+7sbnnmZveQsKtD6nKgOnbd8KS/mGZT1B0KeC0OdYpnq7RPyxZVtLWl7tlWbPDjIDdh1ZTMTzsZPq/UQ4Jw43lt76Q/AZP4rQRJA0/cX9GbMMQihiTOBDKtk4Ae6+QcTmt9bQ30Chw2ysd2nN3kjar9q2PTwxvxEn600aqXNnQTcq7t5Cwg3bw9N7DXYYOxLtdeBGxMnJCthzEJk+3iOD/juLWO5UMc44vV33y2WbcEhdwgqn20LOys78DExgoqg/nFqvpFY5jAc3q89PEm', 51129114, false, '1.1.8',
   'Serenut OS v1.1.9+20 — Satış ve stok verilerinin tüm cihazlara toplu basılması ve anlık eşitlenmesi düzeltildi.',
   'active', 100, 'system');

SELECT id, version_code, platform, sha256_hash, length(signature) as sig_len, status FROM app_versions WHERE version_code = '1.1.9+20';
