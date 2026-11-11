import 'package:flutter/painting.dart';

/// The elevation shadows of acme_shop.
abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}
