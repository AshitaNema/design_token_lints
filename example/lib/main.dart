import 'package:acme_shop/screens/checkout.dart';
import 'package:acme_shop/screens/legacy_checkout.dart';
import 'package:flutter/material.dart';

void main() => runApp(const AcmeShop());

/// Shows both checkout screens side by side.
class AcmeShop extends StatelessWidget {
  const AcmeShop({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(child: Checkout()),
              Expanded(child: LegacyCheckout()),
            ],
          ),
        ),
      ),
    );
  }
}
