/// A minimal stand-in for the parts of `package:flutter/material.dart` that
/// the rules look at.
const fakeFlutterMaterial = r'''
class Widget {
  const Widget();
}

class Color {
  const Color(int value);
  const Color.fromARGB(int a, int r, int g, int b);
  const Color.fromRGBO(int r, int g, int b, double opacity);
  const Color.from({
    required double alpha,
    required double red,
    required double green,
    required double blue,
  });
  Color withOpacity(double opacity) => this;
}

class MaterialColor extends Color {
  const MaterialColor(super.primary, Map<int, Color> swatch);
  Color get shade50 => this;
  Color get shade100 => this;
  Color get shade200 => this;
  Color get shade500 => this;
  Color get shade900 => this;
  Color operator [](int index) => this;
}

class Colors {
  static const Color transparent = Color(0x00000000);
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const MaterialColor red = MaterialColor(0xFFF44336, <int, Color>{});
  static const MaterialColor blue = MaterialColor(0xFF2196F3, <int, Color>{});
}

class EdgeInsets {
  const EdgeInsets.all(double value);
  const EdgeInsets.symmetric({double vertical = 0, double horizontal = 0});
  const EdgeInsets.only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  });
  const EdgeInsets.fromLTRB(double l, double t, double r, double b);
}

class EdgeInsetsDirectional {
  const EdgeInsetsDirectional.all(double value);
  const EdgeInsetsDirectional.only({
    double start = 0,
    double top = 0,
    double end = 0,
    double bottom = 0,
  });
}

class SizedBox extends Widget {
  const SizedBox({double? width, double? height, Widget? child});
  const SizedBox.square({double? dimension, Widget? child});
}

class Radius {
  const Radius.circular(double radius);
  static const Radius zero = Radius.circular(0);
}

class BorderRadius {
  const BorderRadius.all(Radius radius);
  const BorderRadius.circular(double radius);
  const BorderRadius.only({
    Radius topLeft = Radius.zero,
    Radius topRight = Radius.zero,
    Radius bottomLeft = Radius.zero,
    Radius bottomRight = Radius.zero,
  });
}

class FontWeight {
  const FontWeight._();
  static const FontWeight w400 = FontWeight._();
  static const FontWeight w600 = FontWeight._();
  static const FontWeight normal = w400;
  static const FontWeight bold = FontWeight._();
}

class TextStyle {
  const TextStyle({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    String? fontFamily,
  });
  TextStyle copyWith({Color? color}) => this;
}

class Offset {
  const Offset(double dx, double dy);
  static const Offset zero = Offset(0, 0);
}

class BoxShadow {
  const BoxShadow({
    Color color = const Color(0xFF000000),
    Offset offset = Offset.zero,
    double blurRadius = 0,
    double spreadRadius = 0,
  });
}

class BoxDecoration {
  const BoxDecoration({
    Color? color,
    BorderRadius? borderRadius,
    List<BoxShadow>? boxShadow,
  });
}

class Text extends Widget {
  const Text(String data, {TextStyle? style});
}

class ElevatedButton extends Widget {
  const ElevatedButton({required void Function()? onPressed, Widget? child});
  const ElevatedButton.icon({
    required void Function()? onPressed,
    required Widget icon,
    required Widget label,
  });

  static ButtonStyle styleFrom({double? elevation, Color? backgroundColor}) =>
      const ButtonStyle();
}

class ButtonStyle {
  const ButtonStyle();
}

class Icon extends Widget {
  const Icon(Object? icon, {double? size, Color? color});
}

class ImageIcon extends Widget {
  const ImageIcon(Object? image, {double? size});
}

class IconButton extends Widget {
  const IconButton({
    required void Function()? onPressed,
    required Widget icon,
    double? iconSize,
  });
  const IconButton.filled({
    required void Function()? onPressed,
    required Widget icon,
    double? iconSize,
  });
}

class IconThemeData {
  const IconThemeData({double? size, Color? color});
}

class Material extends Widget {
  const Material({double elevation = 0.0, Widget? child});
}

class Card extends Widget {
  const Card({double? elevation, Widget? child});
  const Card.outlined({double? elevation, Widget? child});
}

class AppBar extends Widget {
  AppBar({double? elevation, double? scrolledUnderElevation});
}

class FloatingActionButton extends Widget {
  const FloatingActionButton({
    required void Function()? onPressed,
    double? elevation,
  });
  const FloatingActionButton.extended({
    required void Function()? onPressed,
    required Widget label,
    double? elevation,
  });
}

class PhysicalModel extends Widget {
  const PhysicalModel({
    double elevation = 0.0,
    required Color color,
    Widget? child,
  });
}

class Padding extends Widget {
  const Padding({required EdgeInsets padding, Widget? child});
}

class Container extends Widget {
  const Container({
    EdgeInsets? padding,
    EdgeInsets? margin,
    BoxDecoration? decoration,
    Widget? child,
  });
}

class DefaultTextStyle extends Widget {
  const DefaultTextStyle({required TextStyle style, required Widget child});
}
class BuildContext {}

class ColorScheme {
  const ColorScheme({
    required this.primary,
    Color? primaryContainer,
    this.contrastLevel = 0,
  }) : _primaryContainer = primaryContainer;
  final Color primary;
  final Color? _primaryContainer;
  Color get primaryContainer => _primaryContainer ?? primary;
  final double contrastLevel;
  ColorScheme copyWith({Color? primary}) => this;
  static ColorScheme of(BuildContext context) =>
      const ColorScheme(primary: Color(0xFF000000));
}

class TextTheme {
  const TextTheme({this.bodyMedium, this.titleLarge});
  final TextStyle? bodyMedium;
  final TextStyle? titleLarge;
  static TextTheme of(BuildContext context) => const TextTheme();
}

class ThemeData {
  const ThemeData({required this.colorScheme, required this.textTheme});
  final ColorScheme colorScheme;
  final TextTheme textTheme;
}

class Theme {
  static ThemeData of(BuildContext context) => const ThemeData(
    colorScheme: ColorScheme(primary: Color(0xFF000000)),
    textTheme: TextTheme(),
  );
}
''';

/// A minimal stand-in for `package:material_ui/material_ui.dart`.
///
/// Like the real package, it declares its own `Colors` and `ElevatedButton`
/// instead of re-exporting Flutter's.
const fakeMaterialUi = r'''
import 'package:flutter/material.dart'
    show BuildContext, Color, MaterialColor, TextStyle, Widget;
export 'package:flutter/material.dart'
    hide Colors, ColorScheme, ElevatedButton, TextTheme, Theme, ThemeData;

abstract final class Colors {
  static const Color transparent = Color(0x00000000);
  static const Color white = Color(0xFFFFFFFF);
  static const MaterialColor red = MaterialColor(0xFFF44336, <int, Color>{});
  static const MaterialColor blue = MaterialColor(0xFF2196F3, <int, Color>{});
}

class ElevatedButton extends Widget {
  const ElevatedButton({required void Function()? onPressed, Widget? child});
}

class BuildContext {}

class ColorScheme {
  const ColorScheme({
    required this.primary,
    Color? primaryContainer,
    this.contrastLevel = 0,
  }) : _primaryContainer = primaryContainer;
  final Color primary;
  final Color? _primaryContainer;
  Color get primaryContainer => _primaryContainer ?? primary;
  final double contrastLevel;
  ColorScheme copyWith({Color? primary}) => this;
  static ColorScheme of(BuildContext context) =>
      const ColorScheme(primary: Color(0xFF000000));
}

class TextTheme {
  const TextTheme({this.bodyMedium, this.titleLarge});
  final TextStyle? bodyMedium;
  final TextStyle? titleLarge;
  static TextTheme of(BuildContext context) => const TextTheme();
}

class ThemeData {
  const ThemeData({required this.colorScheme, required this.textTheme});
  final ColorScheme colorScheme;
  final TextTheme textTheme;
}

class Theme {
  static ThemeData of(BuildContext context) => const ThemeData(
    colorScheme: ColorScheme(primary: Color(0xFF000000)),
    textTheme: TextTheme(),
  );
}
''';

/// A minimal stand-in for `package:cupertino_ui/cupertino_ui.dart`.
const fakeCupertinoUi = r'''
import 'package:flutter/material.dart' show Widget;

class CupertinoButton extends Widget {
  const CupertinoButton({required void Function()? onPressed, Widget? child});
}
''';
