import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';

class PinVerificationResult {
  final bool success;
  final String? userId;
  final String? userName;

  PinVerificationResult({required this.success, this.userId, this.userName});
}

class PinVerificationDialog extends ConsumerStatefulWidget {
  final String actionTitle;
  final bool requireConfirm;

  const PinVerificationDialog({
    super.key,
    required this.actionTitle,
    this.requireConfirm = false,
  });

  @override
  ConsumerState<PinVerificationDialog> createState() => _PinVerificationDialogState();
}

class _PinVerificationDialogState extends ConsumerState<PinVerificationDialog> {
  String _pin = '';
  String? _error;
  bool _isLocked = false;
  int _lockoutSecondsRemaining = 0;
  Timer? _countdownTimer;
  bool _isConfirmChecked = false;

  @override
  void initState() {
    super.initState();
    _checkLockout();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLockout() async {
    final authService = ref.read(authServiceProvider);
    final user = await authService.getCurrentUser();
    if (user == null) return;

    final repo = await ref.read(userRepositoryProvider);
    final lockoutData = await repo.getFailedPinAttempts(user.id);
    final lockedUntilStr = lockoutData['locked_until'] as String?;
    if (lockedUntilStr != null) {
      final lockedUntil = DateTime.tryParse(lockedUntilStr);
      if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
        setState(() {
          _isLocked = true;
          _lockoutSecondsRemaining = lockedUntil.difference(DateTime.now()).inSeconds;
        });
        _startTimer();
      }
    }
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockoutSecondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _isLocked = false;
          _lockoutSecondsRemaining = 0;
          _error = null;
        });
      } else {
        setState(() {
          _lockoutSecondsRemaining--;
        });
      }
    });
  }

  void _onKeyPress(String key) {
    if (_isLocked) return;
    if (_pin.length >= 4) return;
    setState(() {
      _pin += key;
      _error = null;
    });

    if (_pin.length == 4) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _verifyPin() async {
    final authService = ref.read(authServiceProvider);
    final result = await authService.verifyCurrentUserPin(_pin);

    if (result.success) {
      if (widget.requireConfirm && !_isConfirmChecked) {
        setState(() {
          _error = 'Lütfen tehlikeli işlemi onay kutusunu işaretleyerek onaylayın.';
          _pin = '';
        });
        return;
      }
      if (mounted) {
        Navigator.pop(
          context,
          PinVerificationResult(
            success: true,
            userId: result.approverUserId,
            userName: result.approverUserName,
          ),
        );
      }
    } else {
      // Check if it got locked
      final user = await authService.getCurrentUser();
      if (user != null) {
        final repo = await ref.read(userRepositoryProvider);
        final lockoutData = await repo.getFailedPinAttempts(user.id);
        final attempts = lockoutData['failed_pin_attempts'] as int? ?? 0;
        final lockedUntilStr = lockoutData['locked_until'] as String?;
        
        setState(() {
          _pin = '';
          if (lockedUntilStr != null) {
            _isLocked = true;
            final lockedUntil = DateTime.parse(lockedUntilStr);
            _lockoutSecondsRemaining = lockedUntil.difference(DateTime.now()).inSeconds;
            _error = 'Çok fazla hatalı deneme! Cihaz kilitlendi.';
            _startTimer();
          } else {
            final remaining = 5 - attempts;
            _error = 'Hatalı PIN girdiniz. Kalan deneme: $remaining';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: const Color(0xFF0F172A), // Premium Dark Slate background
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title & Icon
            const Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 40),
            const SizedBox(height: 12),
            const Text(
              'Yönetici Doğrulaması',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${currentUser?.name ?? "Yönetici"} olarak doğrulamak için PIN girin.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),

            // Action Details Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.actionTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Require Confirm Checkbox (For dangerous actions)
            if (widget.requireConfirm) ...[
              Row(
                children: [
                  Checkbox(
                    value: _isConfirmChecked,
                    onChanged: (val) {
                      setState(() {
                        _isConfirmChecked = val ?? false;
                        _error = null;
                      });
                    },
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Color(0xFFEF4444); // Red warning color
                      }
                      return const Color(0xFF334155);
                    }),
                    checkColor: Colors.white,
                  ),
                  const Expanded(
                    child: Text(
                      'Bu işlemin geri alınamaz olduğunu anlıyor ve onaylıyorum.',
                      style: TextStyle(
                        color: Color(0xFFF8FAFC),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // PIN Dots Indicator
            if (!_isLocked)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final active = index < _pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? const Color(0xFFF59E0B) : const Color(0xFF334155),
                      boxShadow: active
                          ? [
                              const BoxShadow(
                                color: Color(0xFFF59E0B),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ]
                          : [],
                    ),
                  );
                }),
              )
            else
              // Lockout countdown timer widget
              Column(
                children: [
                  const Icon(Icons.timer_outlined, color: Color(0xFFEF4444), size: 28),
                  const SizedBox(height: 6),
                  Text(
                    'Güvenlik kilidi devrede. Kalan süre:\n$_lockoutSecondsRemaining saniye',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Error Message (If any)
            if (_error != null)
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFF87171),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 20),

            // Custom Keypad
            Opacity(
              opacity: _isLocked ? 0.3 : 1.0,
              child: IgnorePointer(
                ignoring: _isLocked,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['1', '2', '3'].map((k) => _buildKey(k)).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['4', '5', '6'].map((k) => _buildKey(k)).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['7', '8', '9'].map((k) => _buildKey(k)).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const SizedBox(width: 60, height: 60), // Empty spacer
                        _buildKey('0'),
                        _buildBackspaceKey(),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Close / Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context, PinVerificationResult(success: false)),
              child: const Text(
                'İptal Et',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(String value) {
    return GestureDetector(
      onTap: () => _onKeyPress(value),
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return GestureDetector(
      onTap: _onBackspace,
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 20),
      ),
    );
  }
}
