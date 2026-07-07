part of '../../settings_page.dart';

// Extracted User Management sheets/dialogs for SettingsPage
extension SettingsUserManagementSheets on _SettingsPageState {
  void _showUserManagementPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Consumer(
          builder: (routeCtx, ref, child) => StatefulBuilder(
            builder: (ctx, setPageState) {
              final authService = ref.read(authServiceProvider);
              return FutureBuilder<List<AuthUser>>(
                future: authService.getUsers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const FullScreenSettingsPage(
                      title: 'Kullanıcı Yönetimi',
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
                        ),
                      ),
                    );
                  }

                  final users = snapshot.data ?? [];
                  final currentUser = ref.read(currentUserProvider);

                  return FullScreenSettingsPage(
                    title: 'Kullanıcı Yönetimi',
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, color: _kGreen, size: 28),
                        onPressed: () => _showAddUserDialog(ctx, () {
                          setPageState(() {});
                        }),
                      ),
                    ],
                    child: users.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_outline_rounded, size: 64, color: _kTextSecondary),
                                  SizedBox(height: 16),
                                  Text(
                                    'Henüz kullanıcı eklenmemiş.',
                                    style: TextStyle(color: _kTextSecondary, fontSize: 15),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Sağ üstteki + butonuyla yeni kullanıcı ekleyin.',
                                    style: TextStyle(color: _kTextSecondary, fontSize: 13),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _kBorderColor),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: users.length,
                              separatorBuilder: (c, i) => const Divider(height: 1, color: _kBorderColor),
                              itemBuilder: (c, idx) {
                                final u = users[idx];
                                final initials = u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U';
                                final roleLabel = switch (u.role) {
                                  UserRole.admin => 'Yönetici',
                                  UserRole.manager => 'Müdür',
                                  UserRole.cashier => 'Kasiyer',
                                  UserRole.staff => 'Personel',
                                };
                                final isCurrent = currentUser?.id == u.id;

                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: _kGreen.withOpacity(0.12),
                                    child: Text(
                                      initials,
                                      style: const TextStyle(
                                        color: _kGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    u.name + (isCurrent ? ' (Siz)' : ''),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: _kTextPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    roleLabel,
                                    style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Yetki butonu
                                      TextButton.icon(
                                        onPressed: () => _showPermissionsSheet(ctx, ref, u, () => setPageState(() {})),
                                        icon: const Icon(Icons.shield_outlined, size: 16, color: _kGreen),
                                        label: const Text('Yetkiler', style: TextStyle(color: _kGreen, fontSize: 12, fontWeight: FontWeight.w600)),
                                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                                      ),
                                      const Icon(Icons.chevron_right_rounded, color: _kTextSecondary),
                                    ],
                                  ),
                                  onTap: () => _showEditUserDialog(ctx, u, isCurrent, () {
                                    setPageState(() {});
                                  }),
                                );
                              },
                            ),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Granüler Yetki Atama Ekranı ────────────────────────────────────────────
  void _showPermissionsSheet(BuildContext context, WidgetRef ref, AuthUser user, VoidCallback onSaved) {
    final authService = ref.read(authServiceProvider);
    List<String> selectedPerms = List<String>.from(user.permissions);

    final permGroups = [
      (label: 'Satış', icon: Icons.point_of_sale_rounded, perms: [
        (value: 'sales:view', label: 'Satışları görüntüle'),
        (value: 'sales:create', label: 'Satış oluştur'),
        (value: 'sales:edit', label: 'Satış düzenle'),
        (value: 'sales:print', label: 'Fiş yazdır'),
      ]),
      (label: 'Sipariş', icon: Icons.shopping_bag_outlined, perms: [
        (value: 'orders:view', label: 'Siparişleri görüntüle'),
        (value: 'orders:create', label: 'Sipariş oluştur'),
        (value: 'orders:edit', label: 'Sipariş düzenle'),
        (value: 'orders:deliver', label: 'Sipariş teslim et'),
      ]),
      (label: 'Müşteri', icon: Icons.people_outline_rounded, perms: [
        (value: 'customers:view', label: 'Müşterileri görüntüle'),
        (value: 'customers:create', label: 'Müşteri ekle'),
        (value: 'customers:edit', label: 'Müşteri düzenle'),
        (value: 'customers:delete', label: 'Müşteri sil'),
      ]),
      (label: 'Finans / Ödeme', icon: Icons.account_balance_wallet_outlined, perms: [
        (value: 'payments:view', label: 'Cari görüntüle'),
        (value: 'payments:record', label: 'Tahsilat al'),
        (value: 'payments:reverse', label: 'Borç sil'),
      ]),
      (label: 'Stok', icon: Icons.inventory_2_outlined, perms: [
        (value: 'inventory:view', label: 'Stok görüntüle'),
        (value: 'inventory:adjust', label: 'Stok düzenle'),
        (value: 'inventory:transfer', label: 'Stok transfer'),
      ]),
      (label: 'Raporlar', icon: Icons.bar_chart_rounded, perms: [
        (value: 'reports:view', label: 'Raporları görüntüle'),
        (value: 'reports:financial', label: 'Finansal raporlar'),
        (value: 'reports:inventory', label: 'Stok raporları'),
      ]),
      (label: 'Yönetim / Sistem', icon: Icons.admin_panel_settings_outlined, perms: [
        (value: 'admin:settings', label: 'Ayarları yönet'),
        (value: 'admin:users', label: 'Kullanıcıları yönet'),
      ]),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (statefulCtx, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 36, height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${user.name} — Yetkiler',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: _kTextPrimary),
                            ),
                            Text(
                              '${selectedPerms.length} / ${Permission.values.length} yetki aktif',
                              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final updated = user.copyWith(permissions: selectedPerms);
                          await authService.updateUser(updated);
                          onSaved();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _kBorderColor),
                // Permission groups
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: permGroups.length,
                    itemBuilder: (ctx, groupIdx) {
                      final group = permGroups[groupIdx];
                      final groupPerms = group.perms;
                      final allSelected = groupPerms.every((p) => selectedPerms.contains(p.value));

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorderColor),
                        ),
                        child: Column(
                          children: [
                            // Group header with select-all toggle
                            InkWell(
                              onTap: () {
                                setSheetState(() {
                                  if (allSelected) {
                                    selectedPerms.removeWhere((p) => groupPerms.any((gp) => gp.value == p));
                                  } else {
                                    for (final p in groupPerms) {
                                      if (!selectedPerms.contains(p.value)) {
                                        selectedPerms.add(p.value);
                                      }
                                    }
                                  }
                                });
                              },
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Row(
                                  children: [
                                    Icon(group.icon, size: 18, color: _kTextSecondary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        group.label,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _kTextPrimary),
                                      ),
                                    ),
                                    Text(
                                      allSelected ? 'Hepsi Seçili' : 'Hepsini Seç',
                                      style: TextStyle(
                                        color: allSelected ? _kGreen : _kTextSecondary,
                                        fontSize: 12,
                                        fontWeight: allSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      allSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                                      color: allSelected ? _kGreen : _kTextSecondary,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: _kBorderColor),
                            // Individual permissions
                            ...groupPerms.asMap().entries.map((entry) {
                              final idx2 = entry.key;
                              final perm = entry.value;
                              final isEnabled = selectedPerms.contains(perm.value);
                              return Column(
                                children: [
                                  if (idx2 > 0) const Divider(height: 1, color: _kBorderColor, indent: 16),
                                  ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                    title: Text(
                                      perm.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isEnabled ? _kTextPrimary : _kTextSecondary,
                                        fontWeight: isEnabled ? FontWeight.w500 : FontWeight.normal,
                                      ),
                                    ),
                                    trailing: Switch.adaptive(
                                      value: isEnabled,
                                      activeColor: _kGreen,
                                      onChanged: (val) {
                                        setSheetState(() {
                                          if (val) {
                                            selectedPerms.add(perm.value);
                                          } else {
                                            selectedPerms.remove(perm.value);
                                          }
                                        });
                                      },
                                    ),
                                    onTap: () {
                                      setSheetState(() {
                                        if (isEnabled) {
                                          selectedPerms.remove(perm.value);
                                        } else {
                                          selectedPerms.add(perm.value);
                                        }
                                      });
                                    },
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddUserDialog(BuildContext context, VoidCallback onSaved) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    UserRole selectedRole = UserRole.cashier;
    final formKey = GlobalKey<FormState>();
    bool obscureText = true;

    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (dialogCtx, ref, child) => StatefulBuilder(
          builder: (statefulCtx, dialogSetState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Yeni Kullanıcı Ekle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: Form(
              key: formKey,
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
                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Ad Soyad gerekli' : null,
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'E-posta gerekli';
                        if (!v.contains('@') || !v.contains('.')) return 'Geçersiz e-posta';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UserRole>(
                      value: selectedRole,
                      style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                      decoration: InputDecoration(
                        labelText: 'Rol',
                        prefixIcon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: UserRole.values.map((role) {
                        final label = switch (role) {
                          UserRole.admin => 'Yönetici',
                          UserRole.manager => 'Müdür',
                          UserRole.cashier => 'Kasiyer',
                          UserRole.staff => 'Personel',
                        };
                        return DropdownMenuItem(value: role, child: Text(label));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          dialogSetState(() {
                            selectedRole = val;
                          });
                        }
                      },
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
                            dialogSetState(() {
                              obscureText = !obscureText;
                            });
                          },
                          child: Icon(
                            obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            size: 18,
                          ),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Şifre gerekli' : null,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    final authService = ref.read(authServiceProvider);
                    final id = 'user-${DateTime.now().millisecondsSinceEpoch}';
                    final newUser = AuthUser(
                      id: id,
                      name: nameCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      role: selectedRole,
                      permissions: AuthService.getPermissionsForRole(selectedRole),
                      createdAt: DateTime.now(),
                    );
                    await authService.createUser(newUser, passCtrl.text.trim());
                    ref.read(auditLogServiceProvider).log(
                      action: 'user_created',
                      details: '{"id":"${newUser.id}","name":"${newUser.name}","role":"${newUser.role.name}"}',
                    );
                    onSaved();
                    if (context.mounted) Navigator.pop(ctx);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Ekle', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, AuthUser user, bool isCurrent, VoidCallback onSaved) {
    final nameCtrl = TextEditingController(text: user.name);
    final emailCtrl = TextEditingController(text: user.email);
    final passCtrl = TextEditingController();
    UserRole selectedRole = user.role;
    final formKey = GlobalKey<FormState>();
    bool obscureText = true;

    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (dialogCtx, ref, child) => StatefulBuilder(
          builder: (statefulCtx, dialogSetState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('${user.name} Düzenle', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: Form(
              key: formKey,
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
                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Ad Soyad gerekli' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'E-posta',
                        prefixIcon: const Icon(Icons.email_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'E-posta gerekli';
                        if (!v.contains('@') || !v.contains('.')) return 'Geçersiz e-posta';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UserRole>(
                      value: selectedRole,
                      disabledHint: Text(switch (selectedRole) {
                        UserRole.admin => 'Yönetici',
                        UserRole.manager => 'Müdür',
                        UserRole.cashier => 'Kasiyer',
                        UserRole.staff => 'Personel',
                      }),
                      onChanged: isCurrent ? null : (val) {
                        if (val != null) {
                          dialogSetState(() {
                            selectedRole = val;
                          });
                        }
                      },
                      style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                      decoration: InputDecoration(
                        labelText: 'Rol',
                        prefixIcon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: UserRole.values.map((role) {
                        final label = switch (role) {
                          UserRole.admin => 'Yönetici',
                          UserRole.manager => 'Müdür',
                          UserRole.cashier => 'Kasiyer',
                          UserRole.staff => 'Personel',
                        };
                        return DropdownMenuItem(value: role, child: Text(label));
                      }).toList(),
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
                            dialogSetState(() {
                              obscureText = !obscureText;
                            });
                          },
                          child: Icon(
                            obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            size: 18,
                          ),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (!isCurrent)
                TextButton(
                  onPressed: () {
                    _showConfirmDeleteUserDialog(ctx, user, () {
                      onSaved();
                      Navigator.pop(ctx);
                    });
                  },
                  child: const Text('Sil', style: TextStyle(color: _kPink, fontWeight: FontWeight.bold)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    final authService = ref.read(authServiceProvider);
                    final updated = user.copyWith(
                      name: nameCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      role: selectedRole,
                      permissions: AuthService.getPermissionsForRole(selectedRole),
                    );
                    await authService.updateUser(updated, password: passCtrl.text.trim());
                    onSaved();
                    if (context.mounted) Navigator.pop(ctx);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirmDeleteUserDialog(BuildContext context, AuthUser user, VoidCallback onDeleted) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (dialogCtx, ref, child) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Kullanıcıyı Sil', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text('${user.name} kullanıcısını silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final authService = ref.read(authServiceProvider);
                await authService.deleteUser(user.id);
                onDeleted();
                if (context.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPink,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Sil', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPinConfigDialog() {
    if (_adminPinCode != null && _adminPinCode!.isNotEmpty) {
      PinGateDialog.checkAndShow(context, title: 'Güvenlik Doğrulaması', onVerified: () {
        _showPinEntryOptionsSheet();
      });
    } else {
      _showNewPinEntrySheet();
    }
  }

  void _showPinEntryOptionsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text(
                'PIN Yönetimi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.lock_open_rounded, color: Colors.red),
                title: const Text('PIN Kilidini Kaldır', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                subtitle: const Text('Admin korumasını devre dışı bırakır'),
                onTap: () async {
                  Navigator.pop(context);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('admin_pin_code');
                  _loadAdminPin();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Yönetici PIN kilidi kaldırıldı.')),
                    );
                  }
                },
              ),
              const _IOSDivider(),
              ListTile(
                leading: const Icon(Icons.mode_edit_outline_outlined, color: _kBlue),
                title: const Text('PIN Kodunu Değiştir', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Yeni 4 haneli PIN belirleyin'),
                onTap: () {
                  Navigator.pop(context);
                  _showNewPinEntrySheet();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showNewPinEntrySheet() {
    final formKey = GlobalKey<FormState>();
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Form(
            key: formKey,
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
                    if (v == null || v.length != 4) return 'PIN tam olarak 4 haneli olmalıdır.';
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        final prefs = await SharedPreferences.getInstance();
                        final hashedPin = PasswordHashService.hashPassword(pinCtrl.text);
                        await prefs.setString('admin_pin_code', hashedPin);
                        // PIN değiştiğinde session cache'i sıfırla
                        PinSessionCache.instance.invalidate();
                        _loadAdminPin();
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Yönetici PIN kodu başarıyla güncellendi.')),
                          );
                        }
                      }
                    },
                    child: const Text('PIN Kaydet', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

