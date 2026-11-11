import 'package:flutter/material.dart';

List<Widget> legacyCheckout() => [
  Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
    decoration: BoxDecoration(
      color: const Color(0xFF1E88E5),
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: const SizedBox(width: 24, height: 13),
  ),
  const Text(
    'Total',
    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
  ),
  const Text('Pay now', style: TextStyle(fontSize: 13, color: Colors.red)),
  ElevatedButton(onPressed: null, child: const SizedBox()),
  Padding(
    padding: const EdgeInsets.only(left: 3, top: 5),
    child: Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
    ),
  ),
];
