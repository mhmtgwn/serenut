import 'package:flutter/material.dart';

class PaymentSection extends StatelessWidget {
  final TextEditingController paymentController;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final Function(double) onPaymentChanged;

  const PaymentSection({
    Key? key,
    required this.paymentController,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.onPaymentChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.payment, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  'Ödeme Bilgileri',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: paymentController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ödenen Tutar',
                      border: OutlineInputBorder(),
                      suffixText: 'TL',
                    ),
                    onChanged: (value) {
                      final payment = double.tryParse(value) ?? 0.0;
                      onPaymentChanged(payment);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    paymentController.text = totalAmount.toStringAsFixed(2);
                    onPaymentChanged(totalAmount);
                  },
                  child: const Text('Tam Ödeme'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Toplam Tutar:'),
                      Text(
                        '${totalAmount.toStringAsFixed(2)} TL',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ödenen:'),
                      Text(
                        '${paidAmount.toStringAsFixed(2)} TL',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kalan:'),
                      Text(
                        '${remainingAmount.toStringAsFixed(2)} TL',
                        style: TextStyle(
                          color:
                              remainingAmount > 0 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
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
