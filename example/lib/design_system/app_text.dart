import 'package:flutter/material.dart';

import 'app_typography.dart';

/// The text widget of acme_shop. Defaults to [AppTypography.body].
class AppText extends StatelessWidget {
  const AppText(this.data, {this.style, super.key});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(data, style: style ?? AppTypography.body);
  }
}
