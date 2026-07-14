import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/providers/auth_provider.dart';
import 'package:serenutos/config/router.dart';

class OperationalErrorPage extends ConsumerStatefulWidget {
  const OperationalErrorPage({super.key});

  @override
  ConsumerState<OperationalErrorPage> createState() => _OperationalErrorPageState();
}

class _OperationalErrorPageState extends ConsumerState<OperationalErrorPage> {
  bool _isLoading = false;

  Future<void> _handleRefresh() async {
    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final success = await authService.refreshEntitlement();
      if (success && mounted) {
        // Router will automatically re-evaluate state based on TrialManager via authNotifierProvider
        // But we can explicitly force a refresh just in case
        ref.read(authNotifierProvider.notifier).checkAuth();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Durum güncellendi, yönlendiriliyorsunuz...')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Abonelik durumu henüz aktif değil veya internet bağlantısı yok.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('İşlem Kısıtlaması'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              const Text(
                'Abonelik veya lisans durumunuz nedeniyle bazı servisler kullanılamıyor.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Lütfen işletme yöneticinizle iletişime geçin.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _handleRefresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Durumu Yenile'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        ref.read(authNotifierProvider.notifier).logout();
                        context.go(AppRoutes.login);
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Çıkış Yap'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
