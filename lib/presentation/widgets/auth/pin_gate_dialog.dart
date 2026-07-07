import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// ─── PIN Session Cache ────────────────────────────────────────────────────
/// Bir kez doğrulanan PIN yetkisi, 30 dakika boyunca bellekte tutulur.
/// Böylece aynı oturumda birden fazla kez PIN sorulmaz.
/// Şu durumlarda sıfırlanır: logout, kullanıcı değişimi, PIN değişimi, uygulama yeniden başlatma.
class PinSessionCache {
  PinSessionCache._();
  static final PinSessionCache _instance = PinSessionCache._();
  static PinSessionCache get instance => _instance;

  DateTime? _verifiedAt;
  static const _cacheDuration = Duration(minutes: 30);

  bool get isValid {
    if (_verifiedAt == null) return false;
    return DateTime.now().difference(_verifiedAt!) < _cacheDuration;
  }

  void markVerified() {
    _verifiedAt = DateTime.now();
  }

  void invalidate() {
    _verifiedAt = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class PinGateDialog extends StatefulWidget {
  final String savedPin;
  final VoidCallback onVerified;
  final String title;

  const PinGateDialog({
    super.key,
    required this.savedPin,
    required this.onVerified,
    this.title = 'Yönetici Doğrulaması',
  });

  /// Gated check: Session cache'i kontrol eder; geçerliyse PIN göstermez.
  /// PIN yoksa, ya da cache süresi dolmuşsa diyalog gösterir.
  static Future<void> checkAndShow(
    BuildContext context, {
    required VoidCallback onVerified,
    String title = 'Yönetici Doğrulaması',
  }) async {
    // Test ortamında PIN'i atla
    if (const bool.fromEnvironment('FLUTTER_TEST')) {
      onVerified();
      return;
    }

    // Session cache geçerliyse tekrar sorma
    if (PinSessionCache.instance.isValid) {
      onVerified();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString('admin_pin_code');
    if (pin == null || pin.isEmpty) {
      // PIN tanımlı değil, doğrudan geç
      onVerified();
    } else {
      if (!context.mounted) return;
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'PIN Gate',
        barrierColor: Colors.black.withOpacity(0.6),
        transitionDuration: const Duration(milliseconds: 250),
        transitionBuilder: (ctx, anim, _, child) {
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child),
          );
        },
        pageBuilder: (ctx, _, __) {
          return PinGateDialog(
            savedPin: pin,
            onVerified: onVerified,
            title: title,
          );
        },
      );
    }
  }

  @override
  State<PinGateDialog> createState() => _PinGateDialogState();
}

class _PinGateDialogState extends State<PinGateDialog> with SingleTickerProviderStateMixin {
  String _inputPin = '';
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool _isError = false;

  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  bool _isLockedOut = false;
  String _lockoutCountdownText = '';
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);

    _checkLockoutStatus();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLockoutStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutStr = prefs.getString('admin_pin_lockout_until');
    final failedAttempts = prefs.getInt('admin_pin_failed_attempts') ?? 0;

    if (lockoutStr != null) {
      final lockoutTime = DateTime.parse(lockoutStr);
      if (lockoutTime.isAfter(DateTime.now())) {
        setState(() {
          _lockoutUntil = lockoutTime;
          _isLockedOut = true;
          _failedAttempts = failedAttempts;
        });
        _startLockoutCountdown();
        return;
      } else {
        await prefs.remove('admin_pin_lockout_until');
        await prefs.setInt('admin_pin_failed_attempts', 0);
      }
    }

    setState(() {
      _failedAttempts = failedAttempts;
      _isLockedOut = false;
    });
  }

  void _startLockoutCountdown() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockoutUntil == null) {
        timer.cancel();
        return;
      }
      final diff = _lockoutUntil!.difference(DateTime.now());
      if (diff.isNegative) {
        timer.cancel();
        setState(() {
          _isLockedOut = false;
          _lockoutUntil = null;
          _failedAttempts = 0;
        });
        SharedPreferences.getInstance().then((prefs) {
          prefs.remove('admin_pin_lockout_until');
          prefs.setInt('admin_pin_failed_attempts', 0);
        });
      } else {
        setState(() {
          final minutes = diff.inMinutes.toString().padLeft(2, '0');
          final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
          _lockoutCountdownText = '$minutes:$seconds';
        });
      }
    });
  }

  void _onKeyPress(String digit) {
    if (_isLockedOut || _inputPin.length >= 4) return;
    setState(() {
      _inputPin += digit;
      _isError = false;
    });

    if (_inputPin.length == 4) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_isLockedOut || _inputPin.isEmpty) return;
    setState(() {
      _inputPin = _inputPin.substring(0, _inputPin.length - 1);
      _isError = false;
    });
  }

  Future<void> _verifyPin() async {
    if (_isLockedOut) return;

    bool isValid = false;
    final prefs = await SharedPreferences.getInstance();

    if (widget.savedPin.startsWith('pbkdf2\$')) {
      isValid = PasswordHashService.verifyPassword(_inputPin, widget.savedPin);
    } else if (widget.savedPin.length == 64) {
      // Legacy SHA256 hash detection
      final bytes = utf8.encode(_inputPin);
      final digest = sha256.convert(bytes);
      isValid = (digest.toString() == widget.savedPin);
      if (isValid) {
        final hashed = PasswordHashService.hashPassword(_inputPin);
        await prefs.setString('admin_pin_code', hashed);
      }
    } else {
      // Plaintext legacy fallback
      isValid = (_inputPin == widget.savedPin);
      if (isValid) {
        final hashed = PasswordHashService.hashPassword(_inputPin);
        await prefs.setString('admin_pin_code', hashed);
      }
    }
    if (isValid) {
      await prefs.setInt('admin_pin_failed_attempts', 0);
      await prefs.remove('admin_pin_lockout_until');

      // Audit Log Success
      await TelemetryService().logStructured(
        event: 'admin_pin_access_success',
        level: LogLevel.info,
        metadata: {'title': widget.title},
      );

      PinSessionCache.instance.markVerified();
      if (mounted) {
        Navigator.pop(context);
        widget.onVerified();
      }
    } else {
      final newFailed = _failedAttempts + 1;
      await prefs.setInt('admin_pin_failed_attempts', newFailed);

      if (newFailed >= 5) {
        final lockoutUntil = DateTime.now().add(const Duration(minutes: 5));
        await prefs.setString('admin_pin_lockout_until', lockoutUntil.toIso8601String());

        // Audit Log Lockout
        await TelemetryService().logStructured(
          event: 'admin_pin_lockout_triggered',
          level: LogLevel.critical,
          metadata: {'lockout_until': lockoutUntil.toIso8601String()},
        );

        setState(() {
          _isLockedOut = true;
          _lockoutUntil = lockoutUntil;
          _failedAttempts = newFailed;
          _inputPin = '';
          _isError = true;
        });
        _startLockoutCountdown();
      } else {
        // Audit Log Failure Attempt
        await TelemetryService().logStructured(
          event: 'admin_pin_access_failure_attempt',
          level: LogLevel.warning,
          metadata: {
            'failed_attempts': newFailed,
            'remaining_attempts': 5 - newFailed,
          },
        );

        setState(() {
          _failedAttempts = newFailed;
          _isError = true;
          _inputPin = '';
        });
        _shakeController.forward(from: 0.0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lock icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLockedOut ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                ),
                child: Icon(
                  _isLockedOut ? Icons.gpp_bad_rounded : Icons.lock_rounded,
                  color: _isLockedOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isLockedOut
                    ? 'Çok fazla başarısız deneme'
                    : 'PIN kodunuzu girin',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 24),

              if (_isLockedOut) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Cihaz Geçici Olarak Kilitlendi',
                        style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Kalan Süre: $_lockoutCountdownText',
                        style: const TextStyle(color: Color(0xFFB91C1C), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ] else ...[
                // PIN Dots with shake animation
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    final shake = _shakeAnimation.value;
                    return Transform.translate(
                      offset: Offset(8 * (shake < 0.5 ? shake * 2 : (1.0 - shake) * 2) * (_shakeController.value % 0.1 > 0.05 ? 1 : -1), 0),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final isFilled = index < _inputPin.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isError
                              ? Colors.redAccent
                              : (isFilled
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFE2E8F0)),
                          border: Border.all(
                            color: _isError
                                ? Colors.redAccent
                                : (isFilled
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFCBD5E1)),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                if (_isError) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Hatalı PIN. Kalan deneme: ${5 - _failedAttempts}',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Keypad — büyük tuşlar (80x80)
                _buildKeypadGrid(),
              ],

              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: Colors.grey[500]),
                child: const Text('İptal'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadGrid() {
    return Column(
      children: [
        _buildKeypadRow(['1', '2', '3']),
        const SizedBox(height: 10),
        _buildKeypadRow(['4', '5', '6']),
        const SizedBox(height: 10),
        _buildKeypadRow(['7', '8', '9']),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 80, height: 80), // boşluk
            _buildKeyButton('0'),
            _buildBackspaceButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map(_buildKeyButton).toList(),
    );
  }

  Widget _buildKeyButton(String label) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _onKeyPress(label),
        borderRadius: BorderRadius.circular(16),
        splashColor: const Color(0xFF10B981).withOpacity(0.15),
        child: Container(
          width: 80,
          height: 68,
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _onBackspace,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 80,
          height: 68,
          alignment: Alignment.center,
          child: const Icon(
            Icons.backspace_outlined,
            color: Color(0xFF64748B),
            size: 24,
          ),
        ),
      ),
    );
  }
}
