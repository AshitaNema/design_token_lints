/// The statically evaluated value of a design token.
sealed class TokenValue {
  const TokenValue();
}

/// A plain number: a spacing step or a radius expressed as a `double`.
final class NumberValue extends TokenValue {
  /// Creates a number value.
  const NumberValue(this.value);

  /// The number.
  final double value;

  @override
  bool operator ==(Object other) =>
      other is NumberValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NumberValue($value)';
}

/// An ARGB color.
final class ColorValue extends TokenValue {
  /// Creates a color value from a 32-bit [argb] integer.
  const ColorValue(this.argb);

  /// The color as `0xAARRGGBB`.
  final int argb;

  @override
  bool operator ==(Object other) => other is ColorValue && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() =>
      'ColorValue(0x${argb.toRadixString(16).toUpperCase().padLeft(8, '0')})';
}

/// A circular `Radius`.
final class RadiusValue extends TokenValue {
  /// Creates a radius value.
  const RadiusValue(this.value);

  /// The circular radius.
  final double value;

  @override
  bool operator ==(Object other) =>
      other is RadiusValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RadiusValue($value)';
}

/// A `BorderRadius` with the same circular radius on every corner.
final class BorderRadiusValue extends TokenValue {
  /// Creates a border radius value.
  const BorderRadiusValue(this.value);

  /// The circular radius of every corner.
  final double value;

  @override
  bool operator ==(Object other) =>
      other is BorderRadiusValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BorderRadiusValue($value)';
}

/// The identifying properties of a `TextStyle`.
final class TextStyleValue extends TokenValue {
  /// Creates a text style value.
  const TextStyleValue({
    this.fontSize,
    this.fontWeight,
    this.height,
    this.letterSpacing,
  });

  /// `fontSize`, in logical pixels.
  final double? fontSize;

  /// `fontWeight` as its numeric weight (100 to 900).
  final int? fontWeight;

  /// `height`, as a multiple of the font size.
  final double? height;

  /// `letterSpacing`, in logical pixels.
  final double? letterSpacing;

  @override
  bool operator ==(Object other) =>
      other is TextStyleValue &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.height == height &&
      other.letterSpacing == letterSpacing;

  @override
  int get hashCode => Object.hash(fontSize, fontWeight, height, letterSpacing);

  @override
  String toString() =>
      'TextStyleValue(fontSize: $fontSize, fontWeight: $fontWeight, '
      'height: $height, letterSpacing: $letterSpacing)';
}

/// One `BoxShadow`.
final class ShadowLayer {
  /// Creates a shadow layer.
  const ShadowLayer({
    required this.color,
    this.blurRadius = 0,
    this.spreadRadius = 0,
    this.dx = 0,
    this.dy = 0,
  });

  /// The shadow color as `0xAARRGGBB`.
  final int color;

  /// `blurRadius`.
  final double blurRadius;

  /// `spreadRadius`.
  final double spreadRadius;

  /// The horizontal `offset`.
  final double dx;

  /// The vertical `offset`.
  final double dy;

  @override
  bool operator ==(Object other) =>
      other is ShadowLayer &&
      other.color == color &&
      other.blurRadius == blurRadius &&
      other.spreadRadius == spreadRadius &&
      other.dx == dx &&
      other.dy == dy;

  @override
  int get hashCode => Object.hash(color, blurRadius, spreadRadius, dx, dy);

  @override
  String toString() =>
      'ShadowLayer(color: $color, blur: $blurRadius, spread: $spreadRadius, '
      'offset: ($dx, $dy))';
}

/// A single `BoxShadow` or a `List<BoxShadow>`.
final class ShadowValue extends TokenValue {
  /// Creates a shadow value.
  const ShadowValue(this.layers, {required this.isList});

  /// The layers, in paint order.
  final List<ShadowLayer> layers;

  /// Whether the token is a list (`boxShadow:` value) rather than one shadow.
  final bool isList;

  @override
  bool operator ==(Object other) =>
      other is ShadowValue &&
      other.isList == isList &&
      other.layers.length == layers.length &&
      [
        for (var i = 0; i < layers.length; i++) layers[i] == other.layers[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hash(isList, Object.hashAll(layers));

  @override
  String toString() => 'ShadowValue(isList: $isList, $layers)';
}
