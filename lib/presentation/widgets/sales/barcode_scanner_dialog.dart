import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerDialog extends StatefulWidget {
  final Function(String) onBarcodeScanned;

  const BarcodeScannerDialog({super.key, required this.onBarcodeScanned});

  static Future<void> show(BuildContext context,
      {required Function(String) onBarcodeScanned}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Barcode Scanner',
      pageBuilder: (context, _, __) =>
          BarcodeScannerDialog(onBarcodeScanned: onBarcodeScanned),
    );
  }

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const kGreen = Color(0xFF16A34A);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Scanner View
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (_isScanned) return;
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String? code = barcodes.first.rawValue;
                  if (code != null && code.isNotEmpty) {
                    _isScanned = true;
                    widget.onBarcodeScanned(code);
                    Navigator.pop(context);
                  }
                }
              },
            ),

            // Visual viewfinder target area
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: kGreen, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(21),
                        ),
                      ),
                    ),
                    const Center(
                      child: SizedBox(
                        width: 200,
                        height: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Instruction
            const Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Text(
                'Ürün barkodunu çerçevenin ortasına hizalayın',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),

            // Header actions
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Kamera Barkod Okuyucu',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: ValueListenableBuilder<MobileScannerState>(
                          valueListenable: _controller,
                          builder: (context, state, child) {
                            switch (state.torchState) {
                              case TorchState.off:
                                return const Icon(Icons.flash_off,
                                    color: Colors.white);
                              case TorchState.on:
                                return const Icon(Icons.flash_on,
                                    color: kGreen);
                              default:
                                return const Icon(Icons.flash_off,
                                    color: Colors.white);
                            }
                          },
                        ),
                        onPressed: () => _controller.toggleTorch(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios,
                            color: Colors.white),
                        onPressed: () => _controller.switchCamera(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
