// lib/presentation/pages/onboarding/steps/step2_admin_account.dart
// Adım 2 — Admin Hesabı
// Ad Soyad, Kullanıcı Adı, PIN (4 veya 6 hane), PIN tekrar, opsiyonel şifre
// Parmak izi: "Yakında" info kartı (çalışmayan toggle değil)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/pages/onboarding/onboarding_state.dart';
import 'package:serenutos/presentation/pages/onboarding/widgets/step_indicator.dart';

class Step2AdminAccount extends StatefulWidget {
  final AdminInfo initialData;
  final void Function(AdminInfo data) onComplete;

  const Step2AdminAccount({
    super.key,
    required this.initialData,
    required this.onComplete,
  });

  @override
  State<Step2AdminAccount> createState() => _Step2AdminAccountState();
}

class _Step2AdminAccountState extends State<Step2AdminAccount> {
  final _formKey = GlobalKey<FormState>();
  late AdminInfo _data;

  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _pinConfirmCtrl;
  late final TextEditingController _passwordCtrl;

  bool _obscurePassword = true;
  bool _showPasswordField = false;
  int  _pinLength = 4; // 4 veya 6

  @override
  void initState() {
    super.initState();
    _data          = widget.initialData;
    _fullNameCtrl  = TextEditingController(text: _data.adminFullName);
    _usernameCtrl  = TextEditingController(text: _data.username);
    _pinCtrl       = TextEditingController();
    _pinConfirmCtrl = TextEditingController();
    _passwordCtrl  = TextEditingController();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onComplete(_data.copyWith(
      adminFullName: _fullNameCtrl.text.trim(),
      username:      _usernameCtrl.text.trim(),
      pin:           _pinCtrl.text,
      pinConfirm:    _pinConfirmCtrl.text,
      password:      _passwordCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: POSColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            _OnboardingHeader(
              title:       'Admin Hesabı',
              stepLabel:   'Adım 2 / 3',
              currentStep: 1,
              onBack:      () => context.go('/onboarding/business'),
            ),

            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? size.width * 0.15 : 20,
                  vertical: 8,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Kimlik Bilgileri Kartı
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionTitle(icon: Icons.manage_accounts_rounded, text: 'Kimlik Bilgileri'),
                            const SizedBox(height: 16),
                            _Field(
                              controller: _fullNameCtrl,
                              label: 'Ad Soyad *',
                              hint: 'Adınız Soyadınız',
                              icon: Icons.person_rounded,
                              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Ad Soyad gerekli' : null,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: _usernameCtrl,
                              label: 'Kullanıcı Adı *',
                              hint: 'kullaniciadi',
                              icon: Icons.alternate_email_rounded,
                              keyboard: TextInputType.text,
                              validator: (v) {
                                if (v?.trim().isEmpty ?? true) return 'Kullanıcı adı gerekli';
                                if ((v?.length ?? 0) < 3) return 'En az 3 karakter olmalı';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // PIN Kartı
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionTitle(icon: Icons.pin_rounded, text: 'Giriş PIN\'i'),
                            const SizedBox(height: 8),
                            Text(
                              'Hızlı giriş için 4 veya 6 haneli PIN belirleyin',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: POSColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            // PIN uzunluk seçici
                            Row(
                              children: [
                                const Text('PIN uzunluğu:',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: POSColors.text)),
                                const SizedBox(width: 12),
                                _PinLengthChip(
                                  label: '4 hane',
                                  selected: _pinLength == 4,
                                  onTap: () => setState(() {
                                    _pinLength = 4;
                                    _pinCtrl.clear();
                                    _pinConfirmCtrl.clear();
                                  }),
                                ),
                                const SizedBox(width: 8),
                                _PinLengthChip(
                                  label: '6 hane',
                                  selected: _pinLength == 6,
                                  onTap: () => setState(() {
                                    _pinLength = 6;
                                    _pinCtrl.clear();
                                    _pinConfirmCtrl.clear();
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // PIN girişi
                            TextFormField(
                              controller: _pinCtrl,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: _pinLength,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: const TextStyle(
                                  fontSize: 24, letterSpacing: 8, color: POSColors.text),
                              decoration: InputDecoration(
                                labelText: 'PIN *',
                                hintText: '•' * _pinLength,
                                counterText: '',
                                prefixIcon: const Icon(Icons.lock_rounded,
                                    size: 20, color: POSColors.textSecondary),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'PIN gerekli';
                                if (v.length != _pinLength) return '$_pinLength haneli PIN girin';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            // PIN tekrar
                            TextFormField(
                              controller: _pinConfirmCtrl,
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              maxLength: _pinLength,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: const TextStyle(
                                  fontSize: 24, letterSpacing: 8, color: POSColors.text),
                              decoration: InputDecoration(
                                labelText: 'PIN Tekrar *',
                                hintText: '•' * _pinLength,
                                counterText: '',
                                prefixIcon: const Icon(Icons.lock_outline_rounded,
                                    size: 20, color: POSColors.textSecondary),
                              ),
                              validator: (v) {
                                if (v != _pinCtrl.text) return 'PIN\'ler eşleşmiyor';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // İsteğe bağlı şifre kartı
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionTitle(icon: Icons.security_rounded, text: 'Ek Güvenlik (İsteğe Bağlı)'),
                            const SizedBox(height: 12),
                            _SwitchTile(
                              icon: Icons.password_rounded,
                              title: 'Güçlü Şifre Ekle',
                              subtitle: 'Yedek giriş yöntemi olarak şifre belirle',
                              value: _showPasswordField,
                              onChanged: (v) => setState(() => _showPasswordField = v),
                            ),
                            if (_showPasswordField) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Şifre',
                                  hintText: 'En az 8 karakter',
                                  prefixIcon: const Icon(Icons.password_rounded,
                                      size: 20, color: POSColors.textSecondary),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: POSColors.textSecondary,
                                    ),
                                    onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                validator: (v) {
                                  if (!_showPasswordField) return null;
                                  if ((v?.length ?? 0) < 8) return 'En az 8 karakter';
                                  return null;
                                },
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Parmak izi: Yakında kartı
                      _ComingSoonCard(
                        icon:    Icons.fingerprint_rounded,
                        title:   'Parmak İzi ile Giriş',
                        message: 'Bu özellik yakında kullanılabilir olacak. Etkinleştirildiğinde PIN yerine parmak izi ile hızlıca giriş yapabileceksiniz.',
                      ),

                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),

            // ── Sonraki Butonu ────────────────────────────────────────────
            _BottomButton(label: 'Sonraki', onTap: _submit),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIN uzunluk chip'i
// ─────────────────────────────────────────────────────────────────────────────
class _PinLengthChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PinLengthChip({
    required this.label, required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? POSColors.green : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? POSColors.green : POSColors.border, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : POSColors.text,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Yakında" bilgi kartı
// ─────────────────────────────────────────────────────────────────────────────
class _ComingSoonCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _ComingSoonCard({
    required this.icon, required this.title, required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: POSColors.border,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: POSColors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: POSColors.text)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: POSColors.amberLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Yakında',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: POSColors.amberDark)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(message,
                    style: const TextStyle(
                        fontSize: 12, color: POSColors.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ortak widget'lar (kopyalanmış — bir sonraki refactor'da shared'e taşınabilir)
// ─────────────────────────────────────────────────────────────────────────────

class _OnboardingHeader extends StatelessWidget {
  final String title;
  final String stepLabel;
  final int currentStep;
  final VoidCallback? onBack;

  const _OnboardingHeader({
    required this.title, required this.stepLabel,
    required this.currentStep, this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  color: POSColors.text,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                const SizedBox(width: 24),
              const Spacer(),
              Text(stepLabel,
                  style: const TextStyle(
                      fontSize: 13, color: POSColors.textSecondary,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              const SizedBox(width: 24),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: StepIndicator(totalSteps: 3, currentStep: currentStep),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800, color: POSColors.text)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: POSColors.border),
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionTitle({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
            color: POSColors.greenLight,
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 17, color: POSColors.green),
      ),
      const SizedBox(width: 10),
      Text(text,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: POSColors.text)),
    ],
  );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller, required this.label, required this.hint,
    required this.icon, this.keyboard, this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboard,
    validator: validator,
    style: const TextStyle(fontSize: 15, color: POSColors.text),
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: POSColors.textSecondary),
    ),
  );
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon, required this.title, required this.subtitle,
    required this.value, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: POSColors.textSecondary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: POSColors.text)),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: POSColors.textSecondary)),
          ],
        ),
      ),
      Switch(value: value, onChanged: onChanged),
    ],
  );
}

class _BottomButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BottomButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: EdgeInsets.fromLTRB(
        20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: POSColors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    ),
  );
}
