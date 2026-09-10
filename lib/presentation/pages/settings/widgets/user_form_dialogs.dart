part of '../../settings_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kullanıcı Ekleme, Düzenleme ve PIN Giriş Formları (User Management)
// ─────────────────────────────────────────────────────────────────────────────

class _AddUserDialog extends ConsumerStatefulWidget {
  final _SettingsPageState pageState;
  final VoidCallback onSaved;

  const _AddUserDialog({required this.pageState, required this.onSaved});

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  UserRole selectedRole = UserRole.cashier;
  bool obscureText = true;

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    usernameCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Yeni Kullanıcı Ekle',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Ad Soyad',
                  prefixIcon:
                      const Icon(Icons.person_outline_rounded, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Ad Soyad gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'E-posta',
                  hintText: 'örn: mehmet@serenut.com',
                  prefixIcon: const Icon(Icons.email_outlined, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'E-posta gerekli';
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Geçersiz e-posta';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                value: selectedRole,
                style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Rol',
                  prefixIcon:
                      const Icon(Icons.admin_panel_settings_outlined, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: UserRole.values.map((role) {
                  final label = switch (role) {
                    UserRole.owner => 'Kurucu/Sahip',
                    UserRole.admin => 'Yönetici',
                    UserRole.sysadmin => 'Sistem Yöneticisi',
                    UserRole.manager => 'Müdür',
                    UserRole.cashier => 'Kasiyer',
                    UserRole.staff => 'Personel',
                  };
                  return DropdownMenuItem(value: role, child: Text(label));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      selectedRole = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: usernameCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Kullanıcı Adı (Opsiyonel)',
                  hintText: 'örn: kasiyer1',
                  prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: obscureText,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'PIN (Opsiyonel)',
                  hintText: 'Sadece rakam',
                  prefixIcon: const Icon(Icons.dialpad_rounded, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passCtrl,
                obscureText: obscureText,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Şifre',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  suffixIcon: GestureDetector(
                    onTap: () {
                      setState(() {
                        obscureText = !obscureText;
                      });
                    },
                    child: Icon(
                      obscureText
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                    ),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Şifre gerekli' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              final authService = ref.read(authServiceProvider);
              final id = 'user-${DateTime.now().millisecondsSinceEpoch}';
              final businessCode =
                  ref.read(currentUserProvider)?.businessCode ?? 'DEFAULT';
              final newUser = AuthUser(
                id: id,
                name: nameCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                username: usernameCtrl.text.trim().isEmpty
                    ? null
                    : usernameCtrl.text.trim(),
                businessCode: businessCode,
                role: selectedRole,
                permissions: AuthService.getPermissionsForRole(selectedRole),
                createdAt: DateTime.now(),
              );
              await authService.createUser(newUser, passCtrl.text.trim(),
                  pin:
                      pinCtrl.text.trim().isEmpty ? null : pinCtrl.text.trim());
              ref.read(auditLogServiceProvider).log(
                    action: 'user_created',
                    details:
                        '{"id":"${newUser.id}","name":"${newUser.name}","role":"${newUser.role.name}"}',
                  );
              widget.onSaved();
              if (context.mounted) Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _kGreen,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Ekle', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _EditUserDialog extends ConsumerStatefulWidget {
  final _SettingsPageState pageState;
  final AuthUser user;
  final bool isCurrent;
  final VoidCallback onSaved;

  const _EditUserDialog({
    required this.pageState,
    required this.user,
    required this.isCurrent,
    required this.onSaved,
  });

  @override
  ConsumerState<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController nameCtrl;
  late final TextEditingController emailCtrl;
  late final TextEditingController passCtrl;
  late final TextEditingController usernameCtrl;
  late final TextEditingController pinCtrl;
  late UserRole selectedRole;
  bool obscureText = true;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.user.name);
    emailCtrl = TextEditingController(text: widget.user.email);
    usernameCtrl = TextEditingController(text: widget.user.username);
    pinCtrl = TextEditingController(); // Don't prefill pin for security
    passCtrl = TextEditingController();
    selectedRole = widget.user.role;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    usernameCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('${widget.user.name} Düzenle',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Ad Soyad',
                  prefixIcon:
                      const Icon(Icons.person_outline_rounded, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Ad Soyad gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'E-posta',
                  prefixIcon: const Icon(Icons.email_outlined, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'E-posta gerekli';
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Geçersiz e-posta';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                value: selectedRole,
                disabledHint: Text(switch (selectedRole) {
                  UserRole.owner => 'Kurucu/Sahip',
                  UserRole.admin => 'Yönetici',
                  UserRole.sysadmin => 'Sistem Yöneticisi',
                  UserRole.manager => 'Müdür',
                  UserRole.cashier => 'Kasiyer',
                  UserRole.staff => 'Personel',
                }),
                onChanged: widget.isCurrent
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() {
                            selectedRole = val;
                          });
                        }
                      },
                style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Rol',
                  prefixIcon:
                      const Icon(Icons.admin_panel_settings_outlined, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: UserRole.values.map((role) {
                  final label = switch (role) {
                    UserRole.owner => 'Kurucu/Sahip',
                    UserRole.admin => 'Yönetici',
                    UserRole.sysadmin => 'Sistem Yöneticisi',
                    UserRole.manager => 'Müdür',
                    UserRole.cashier => 'Kasiyer',
                    UserRole.staff => 'Personel',
                  };
                  return DropdownMenuItem(value: role, child: Text(label));
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: usernameCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Kullanıcı Adı (Opsiyonel)',
                  hintText: 'örn: kasiyer1',
                  prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: obscureText,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Yeni PIN (İsteğe Bağlı)',
                  hintText: 'Değiştirmek istemiyorsanız boş bırakın',
                  prefixIcon: const Icon(Icons.dialpad_rounded, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passCtrl,
                obscureText: obscureText,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Yeni Şifre (İsteğe Bağlı)',
                  hintText: 'Değiştirmek istemiyorsanız boş bırakın',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  suffixIcon: GestureDetector(
                    onTap: () {
                      setState(() {
                        obscureText = !obscureText;
                      });
                    },
                    child: Icon(
                      obscureText
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                    ),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.isCurrent)
          TextButton(
            onPressed: () {
              widget.pageState
                  ._showConfirmDeleteUserDialog(context, widget.user, () {
                widget.onSaved();
                Navigator.pop(context);
              });
            },
            child: const Text('Sil',
                style: TextStyle(color: _kPink, fontWeight: FontWeight.bold)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              final authService = ref.read(authServiceProvider);
              final updated = widget.user.copyWith(
                name: nameCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                username: usernameCtrl.text.trim().isEmpty
                    ? null
                    : usernameCtrl.text.trim(),
                role: selectedRole,
                permissions: selectedRole == widget.user.role
                    ? widget.user.permissions
                    : AuthService.getPermissionsForRole(selectedRole),
              );
              await authService.updateUser(updated,
                  password: passCtrl.text.trim().isEmpty
                      ? null
                      : passCtrl.text.trim(),
                  pin:
                      pinCtrl.text.trim().isEmpty ? null : pinCtrl.text.trim());
              widget.onSaved();
              if (context.mounted) Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _kGreen,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _NewPinEntrySheet extends ConsumerStatefulWidget {
  final _SettingsPageState pageState;

  const _NewPinEntrySheet({required this.pageState});

  @override
  ConsumerState<_NewPinEntrySheet> createState() => _NewPinEntrySheetState();
}

class _NewPinEntrySheetState extends ConsumerState<_NewPinEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final pinCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  @override
  void dispose() {
    pinCtrl.dispose();
    confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Yeni PIN Kodu Belirle',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ayarlar, raporlar ve silme işlemleri için kullanılacak 4 haneli PIN kodu belirleyin.',
              style: TextStyle(color: _kTextSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Yeni PIN (4 Hane)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (v) {
                if (v == null || v.length != 4) {
                  return 'PIN tam olarak 4 haneli olmalıdır.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: confirmCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Yeni PIN Onayla',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (v) {
                if (v != pinCtrl.text) return 'PIN kodları uyusmuyor.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final hashedPin =
                        PasswordHashService.hashPassword(pinCtrl.text);
                    // Write hashed PIN to SQLite settings (single source of truth)
                    final settingsState = ref.read(settingsNotifierProvider);
                    if (settingsState.hasValue) {
                      await ref
                          .read(settingsNotifierProvider.notifier)
                          .updateSettings(settingsState.value!
                              .copyWith(adminPinCode: hashedPin));
                    }
                    widget.pageState._loadAdminPin();
                    if (!context.mounted) return;
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Yönetici PIN kodu başarıyla güncellendi.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('PIN Kaydet',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
