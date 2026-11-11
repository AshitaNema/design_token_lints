import 'package:flutter/material.dart';

class AppButton extends Widget {
  const AppButton({required void Function()? onPressed, Widget? child});
}

class AppText extends Widget {
  const AppText(String data, {TextStyle? style});
}
