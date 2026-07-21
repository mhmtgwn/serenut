import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/hardware/scale_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/hardware_provider.dart';

class LiveScaleDialog extends ConsumerStatefulWidget {
  final ProductEntity product;

  const LiveScaleDialog({super.key, required this.product});

  @override
  ConsumerState<LiveScaleDialog> createState() => _LiveScaleDialogState();
}

class _LiveScaleDialogState extends ConsumerState<LiveScaleDialog> {
  late final ScaleSession _session;
  int? _lastSequence;

  @override
  void initState() {
    super.initState();
    _session = ScaleSession(
      minimumWeightGrams: widget.product.minimumWeightGrams,
    )..start(productId: widget.product.id);
  }

  void _consume(ScaleReading? reading) {
    if (reading == null || reading.sequence == _lastSequence) return;
    _lastSequence = reading.sequence;
    _session.addReading(reading);
  }

  @override
  Widget build(BuildContext context) {
    final hardware = ref.watch(scaleHardwareProvider);
    _consume(hardware.reading);
    final reading = hardware.reading;
    final grams = reading?.netGrams ?? 0;
    final total = widget.product.price * grams / 1000.0;
    final canAccept = _session.state == ScaleSessionState.stable;

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.monitor_weight_rounded),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.product.name)),
      ]),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${(grams / 1000).toStringAsFixed(3)} kg',
            style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            canAccept
                ? 'AĞIRLIK STABİL'
                : hardware.connected
                    ? 'Stabil ağırlık bekleniyor…'
                    : 'Terazi bağlı değil',
            style: TextStyle(
              color: canAccept ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '₺${widget.product.price.toStringAsFixed(2)}/kg  •  Toplam ₺${total.toStringAsFixed(2)}',
          ),
          if (kDebugMode &&
              ref.read(scaleAdapterProvider) is SimulatedScaleAdapter) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              OutlinedButton(
                onPressed: () {
                  final simulator =
                      ref.read(scaleAdapterProvider) as SimulatedScaleAdapter;
                  simulator.emit(grams: 1245);
                  simulator.emit(grams: 1246);
                  simulator.emit(grams: 1245);
                },
                child: const Text('1,245 kg simüle et'),
              ),
              OutlinedButton(
                onPressed: () =>
                    (ref.read(scaleAdapterProvider) as SimulatedScaleAdapter)
                        .emit(grams: 0),
                child: const Text('Sıfırla'),
              ),
            ]),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton.icon(
          onPressed: canAccept
              ? () => Navigator.pop(context, _session.accept().netGrams)
              : null,
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text('Sepete Ekle'),
        ),
      ],
    );
  }
}
