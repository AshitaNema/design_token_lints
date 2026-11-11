import 'package:flutter/material.dart';

/// The checkout screen as it was before the design system existed: every
/// value is hard-coded. Open it in an IDE with the plugin enabled to see the
/// diagnostics and quick fixes.
class LegacyCheckout extends StatelessWidget {
  const LegacyCheckout({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order summary',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Free delivery on orders over \$50',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.only(left: 12, top: 4, right: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text('Total: \$64.00'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: () {}, child: const Text('Pay now')),
        ],
      ),
    );
  }
}
