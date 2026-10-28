import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/hazelnut_calculator.dart';

void main() {
  group('HazelnutCalculator Tests', () {
    test('calculateEffectiveUnitPrice - exact 50 rendiment', () {
      final unitPrice = HazelnutCalculator.calculateEffectiveUnitPrice(
        basePrice50: 130.0,
        rendiment: 50.0,
      );
      expect(unitPrice, 130.0);
    });

    test('calculateEffectiveUnitPrice - higher rendiment (52.5)', () {
      // 130 * (52.5 / 50.0) = 130 * 1.05 = 136.50
      final unitPrice = HazelnutCalculator.calculateEffectiveUnitPrice(
        basePrice50: 130.0,
        rendiment: 52.5,
      );
      expect(unitPrice, 136.50);
    });

    test('calculateEffectiveUnitPrice - lower rendiment (48.0)', () {
      // 130 * (48.0 / 50.0) = 130 * 0.96 = 124.80
      final unitPrice = HazelnutCalculator.calculateEffectiveUnitPrice(
        basePrice50: 130.0,
        rendiment: 48.0,
      );
      expect(unitPrice, 124.80);
    });

    test('calculateNetKg - with sack count and tare per sack', () {
      // Gross: 1250 kg, 20 sacks * 1.0 kg tare = 20 kg tare -> Net: 1230 kg
      final net = HazelnutCalculator.calculateNetKg(
        grossKg: 1250.0,
        sackCount: 20,
        tarePerSack: 1.0,
      );
      expect(net, 1230.0);
    });

    test('calculateNetKg - with manual tare override', () {
      final net = HazelnutCalculator.calculateNetKg(
        grossKg: 1000.0,
        sackCount: 15,
        manualTareKg: 25.0,
      );
      expect(net, 975.0);
    });

    test('calculateTotalAmount', () {
      // 1000 kg * 136.50 TL = 136500.0 TL
      final total = HazelnutCalculator.calculateTotalAmount(
        cutKg: 1000.0,
        effectiveUnitPrice: 136.50,
      );
      expect(total, 136500.0);
    });

    test('calculateWeightedAverageRendiment - first batch', () {
      final avg = HazelnutCalculator.calculateWeightedAverageRendiment(
        currentStockKg: 0.0,
        currentAverageRendiment: 50.0,
        incomingKg: 2000.0,
        incomingRendiment: 53.0,
      );
      expect(avg, 53.0);
    });

    test('calculateWeightedAverageRendiment - blending batches', () {
      // Current: 1000 kg at 50.0
      // Incoming: 1000 kg at 52.0
      // Blend: (50000 + 52000) / 2000 = 102000 / 2000 = 51.0
      final avg = HazelnutCalculator.calculateWeightedAverageRendiment(
        currentStockKg: 1000.0,
        currentAverageRendiment: 50.0,
        incomingKg: 1000.0,
        incomingRendiment: 52.0,
      );
      expect(avg, 51.0);
    });
  });
}

