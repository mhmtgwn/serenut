// lib/presentation/widgets/common/country_code_picker.dart
import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';

class CountryCode {
  final String name;
  final String code;
  final String dialCode;
  final String flag;

  const CountryCode({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryCode &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          dialCode == other.dialCode;

  @override
  int get hashCode => code.hashCode ^ dialCode.hashCode;
}

const kDefaultCountry = CountryCode(
  name: 'Türkiye',
  code: 'TR',
  dialCode: '+90',
  flag: '🇹🇷',
);

const List<CountryCode> kPopularCountries = [
  CountryCode(name: 'Türkiye', code: 'TR', dialCode: '+90', flag: '🇹🇷'),
  CountryCode(name: 'Almanya', code: 'DE', dialCode: '+49', flag: '🇩🇪'),
  CountryCode(name: 'Azerbaycan', code: 'AZ', dialCode: '+994', flag: '🇦🇿'),
  CountryCode(name: 'Hollanda', code: 'NL', dialCode: '+31', flag: '🇳🇱'),
  CountryCode(name: 'Fransa', code: 'FR', dialCode: '+33', flag: '🇫🇷'),
  CountryCode(name: 'Avusturya', code: 'AT', dialCode: '+43', flag: '🇦🇹'),
  CountryCode(name: 'Belçika', code: 'BE', dialCode: '+32', flag: '🇧🇪'),
  CountryCode(name: 'İsviçre', code: 'CH', dialCode: '+41', flag: '🇨🇭'),
  CountryCode(name: 'Birleşik Krallık (İngiltere)', code: 'GB', dialCode: '+44', flag: '🇬🇧'),
  CountryCode(name: 'Amerika Birleşik Devletleri', code: 'US', dialCode: '+1', flag: '🇺🇸'),
  CountryCode(name: 'Kanada', code: 'CA', dialCode: '+1', flag: '🇨🇦'),
  CountryCode(name: 'İsveç', code: 'SE', dialCode: '+46', flag: '🇸🇪'),
  CountryCode(name: 'Danimarka', code: 'DK', dialCode: '+45', flag: '🇩🇰'),
  CountryCode(name: 'Norveç', code: 'NO', dialCode: '+47', flag: '🇳🇴'),
  CountryCode(name: 'İtalya', code: 'IT', dialCode: '+39', flag: '🇮🇹'),
  CountryCode(name: 'İspanya', code: 'ES', dialCode: '+34', flag: '🇪🇸'),
  CountryCode(name: 'Yunanistan', code: 'GR', dialCode: '+30', flag: '🇬🇷'),
  CountryCode(name: 'Bulgaristan', code: 'BG', dialCode: '+359', flag: '🇧🇬'),
  CountryCode(name: 'Rusya', code: 'RU', dialCode: '+7', flag: '🇷🇺'),
  CountryCode(name: 'Ukrayna', code: 'UA', dialCode: '+380', flag: '🇺🇦'),
  CountryCode(name: 'Gürcistan', code: 'GE', dialCode: '+995', flag: '🇬🇪'),
  CountryCode(name: 'Kıbrıs (KKTC/Güney)', code: 'CY', dialCode: '+357', flag: '🇨🇾'),
  CountryCode(name: 'Suudi Arabistan', code: 'SA', dialCode: '+966', flag: '🇸🇦'),
  CountryCode(name: 'Birleşik Arap Emirlikleri', code: 'AE', dialCode: '+971', flag: '🇦🇪'),
  CountryCode(name: 'Katar', code: 'QA', dialCode: '+974', flag: '🇶🇦'),
  CountryCode(name: 'Irak', code: 'IQ', dialCode: '+964', flag: '🇮🇶'),
  CountryCode(name: 'İran', code: 'IR', dialCode: '+98', flag: '🇮🇷'),
  CountryCode(name: 'Kazakistan', code: 'KZ', dialCode: '+7', flag: '🇰🇿'),
  CountryCode(name: 'Özbekistan', code: 'UZ', dialCode: '+998', flag: '🇺🇿'),
];

class CountryParseResult {
  final CountryCode country;
  final String localNumber;

  const CountryParseResult({
    required this.country,
    required this.localNumber,
  });
}

/// Parses any stored raw phone number into its [CountryCode] and clean local number.
CountryParseResult parsePhoneNumber(String? rawPhone) {
  if (rawPhone == null || rawPhone.trim().isEmpty) {
    return const CountryParseResult(
      country: kDefaultCountry,
      localNumber: '',
    );
  }

  var cleaned = rawPhone.trim().replaceAll(RegExp(r'[\s\-()]'), '');

  // 1. Check for dial codes with '+'
  if (cleaned.startsWith('+')) {
    final withoutPlus = cleaned.substring(1);
    for (final c in kPopularCountries) {
      final codeDigits = c.dialCode.replaceAll('+', '');
      if (withoutPlus.startsWith(codeDigits)) {
        return CountryParseResult(
          country: c,
          localNumber: withoutPlus.substring(codeDigits.length),
        );
      }
    }
    // Unknown country with +, default to Turkey or keep as is
    return CountryParseResult(
      country: kDefaultCountry,
      localNumber: withoutPlus,
    );
  }

  // 2. Check for dial codes starting with '00'
  if (cleaned.startsWith('00')) {
    final without00 = cleaned.substring(2);
    for (final c in kPopularCountries) {
      final codeDigits = c.dialCode.replaceAll('+', '');
      if (without00.startsWith(codeDigits)) {
        return CountryParseResult(
          country: c,
          localNumber: without00.substring(codeDigits.length),
        );
      }
    }
  }

  // 3. Check for standard Turkish numbers: 05xx... or 905xx...
  if (cleaned.startsWith('90') && cleaned.length >= 12) {
    return CountryParseResult(
      country: kDefaultCountry,
      localNumber: cleaned.substring(2),
    );
  }
  if (cleaned.startsWith('0') && cleaned.length == 11) {
    return CountryParseResult(
      country: kDefaultCountry,
      localNumber: cleaned.substring(1),
    );
  }

  // 4. Default: Turkey
  return CountryParseResult(
    country: kDefaultCountry,
    localNumber: cleaned,
  );
}

/// Combines selected country and local phone into standard E.164 format (e.g. +4915112345678 or +905321234567).
String formatFullPhoneNumber(CountryCode country, String localNumber) {
  var digits = localNumber.trim().replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';

  // Remove leading zeros from local number if any (e.g., 0151 -> 151)
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.isEmpty) return '';

  return '${country.dialCode}$digits';
}

/// Normalizes any phone number for WhatsApp wa.me links (digits only, e.g. 4915112345678 or 905321234567).
String normalizeForWhatsApp(String phone) {
  final parsed = parsePhoneNumber(phone);
  var digits = parsed.localNumber.replaceAll(RegExp(r'\D'), '');
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  final countryDigits = parsed.country.dialCode.replaceAll('+', '');
  return '$countryDigits$digits';
}

/// Formats a phone number for beautiful, readable display across the UI.
/// e.g. +905321234567 -> 0532 123 45 67
/// e.g. +4915112345678 -> +49 151 12345678
String formatPhoneForDisplay(String? phone) {
  if (phone == null || phone.trim().isEmpty) return '';
  final trimmed = phone.trim();
  final parsed = parsePhoneNumber(trimmed);
  var digits = parsed.localNumber.replaceAll(RegExp(r'\D'), '');
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
  }

  if (parsed.country.code == 'TR') {
    if (digits.length == 10) {
      return '0${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6, 8)} ${digits.substring(8, 10)}';
    }
    return digits.isNotEmpty ? '0$digits' : trimmed;
  }

  // Other countries: +{dialCode} {digits}
  return '${parsed.country.dialCode} $digits'.trim();
}

/// Opens a clean modal dialog to select a country code.
Future<CountryCode?> showCountryPickerModal(
  BuildContext context, {
  CountryCode? current,
}) {
  return showModalBottomSheet<CountryCode>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CountryPickerSheet(current: current ?? kDefaultCountry),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  final CountryCode current;

  const _CountryPickerSheet({required this.current});

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().trim();
    final filtered = kPopularCountries.where((c) {
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.dialCode.contains(q) ||
          c.code.toLowerCase().contains(q);
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Text(
                    'Ülke Kodu Seçin',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Ülke adı veya alan kodu ara (örn. Almanya, +49)...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: POSColors.green, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Eşleşen ülke bulunamadı.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 64),
                      itemBuilder: (ctx, idx) {
                        final country = filtered[idx];
                        final isSelected = country.code == widget.current.code &&
                            country.dialCode == widget.current.dialCode;

                        return ListTile(
                          onTap: () => Navigator.pop(context, country),
                          leading: Text(
                            country.flag,
                            style: const TextStyle(fontSize: 26),
                          ),
                          title: Text(
                            country.name,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? POSColors.greenDark
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                country.dialCode,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isSelected
                                      ? POSColors.greenDark
                                      : const Color(0xFF64748B),
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.check_circle_rounded,
                                    color: POSColors.green, size: 20),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact button to be used as `prefixIcon` in phone input fields.
class CountryCodePrefixWidget extends StatelessWidget {
  final CountryCode country;
  final ValueChanged<CountryCode> onCountryChanged;

  const CountryCodePrefixWidget({
    super.key,
    required this.country,
    required this.onCountryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final selected = await showCountryPickerModal(context, current: country);
          if (selected != null) {
            onCountryChanged(selected);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              country.flag,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 6),
            Text(
              country.dialCode,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 20,
              color: Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Container(
              width: 1,
              height: 24,
              color: const Color(0xFFCBD5E1),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
