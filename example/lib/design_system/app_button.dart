import 'package:flutter/material.dart';

/// The button of acme_shop.
class AppButton extends StatelessWidget {
  const AppButton({required this.onPressed, required this.child, super.key});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(onPressed: onPressed, child: child);
  }
}
