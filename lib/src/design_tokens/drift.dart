import '../config/config.dart';
import '../config/rule_id.dart';
import '../tokens/token_index.dart';
import '../tokens/token_value.dart';
import 'dtcg.dart';

/// A token that differs between the design file and the Dart code.
final class DriftItem {
  /// Creates an item.
  const DriftItem({
    required this.category,
    this.designPath,
    this.dartReference,
    this.designValue,
    this.dartValue,
  });

  /// The category of the token.
  final DesignCategory category;

  /// The dotted path in the design file; `null` when only Dart has it.
  final String? designPath;

  /// The Dart reference, for example `AppColors.brandPrimary`; for a token
  /// only the design file has, the reference it is expected under.
  final String? dartReference;

  /// The design value, described; `null` when only Dart has it.
  final String? designValue;

  /// The Dart value, described; `null` when only the design file has it.
  final String? dartValue;
}

/// The result of comparing a design tokens file with the Dart tokens.
final class DriftReport {
  /// Creates a report.
  const DriftReport({
    required this.missingInDart,
    required this.missingInDesign,
    required this.different,
    required this.skipped,
    required this.matching,
  });

  /// Design tokens without a Dart token of the expected name.
  final List<DriftItem> missingInDart;

  /// Dart tokens that the design file does not have.
  final List<DriftItem> missingInDesign;

  /// Tokens that both have, with different values.
  final List<DriftItem> different;

  /// Design tokens that could not be compared, and why.
  final List<DesignTokenProblem> skipped;

  /// The number of tokens that are the same on both sides.
  final int matching;

  /// Whether the Dart tokens match the design file.
  bool get inSync =>
      missingInDart.isEmpty && missingInDesign.isEmpty && different.isEmpty;
}

/// Compares the [groups] of a design tokens [file] with the Dart tokens in
/// [index].
DriftReport compareDesignTokens(
  DesignTokenFile file,
  TokenIndex index,
  Map<DesignCategory, DesignTokenGroup> groups,
) {
  final missingInDart = <DriftItem>[];
  final missingInDesign = <DriftItem>[];
  final different = <DriftItem>[];
  final skipped = <DesignTokenProblem>[];
  var matching = 0;

  for (final MapEntry(key: category, value: mapping) in groups.entries) {
    final dart = {for (final entry in index.of(category)) entry.name: entry};
    final className = index.of(category).firstOrNull?.className;
    final seen = <String>{};
    for (final MapEntry(key: relative, value: token)
        in file.under(mapping.group).entries) {
      final name = mapping.names[relative] ?? camelCaseName(relative);
      if (name == null) {
        skipped.add(
          DesignTokenProblem(
            token.name,
            'no Dart name can be derived; add it under "names"',
          ),
        );
        continue;
      }
      // A token that cannot be compared is still present in the design
      // file, so its Dart counterpart is not reported as missing there.
      seen.add(name);
      final TokenValue designValue;
      try {
        designValue = designValueOf(category, token);
      } on FormatException catch (error) {
        skipped.add(DesignTokenProblem(token.name, error.message));
        continue;
      }
      final entry = dart[name];
      final reference = entry?.reference ?? '${className ?? '?'}.$name';
      if (entry == null) {
        missingInDart.add(
          DriftItem(
            category: category,
            designPath: token.name,
            dartReference: reference,
            designValue: describeValue(designValue),
          ),
        );
      } else if (!sameValue(entry.value, designValue)) {
        different.add(
          DriftItem(
            category: category,
            designPath: token.name,
            dartReference: reference,
            designValue: describeValue(designValue),
            dartValue: describeValue(entry.value),
          ),
        );
      } else {
        matching++;
      }
    }
    for (final MapEntry(key: name, value: entry) in dart.entries) {
      if (seen.contains(name)) continue;
      missingInDesign.add(
        DriftItem(
          category: category,
          dartReference: entry.reference,
          dartValue: describeValue(entry.value),
        ),
      );
    }
  }
  return DriftReport(
    missingInDart: missingInDart,
    missingInDesign: missingInDesign,
    different: different,
    skipped: skipped,
    matching: matching,
  );
}

/// The Dart member name for a design token path relative to its group:
/// `brand.primary` and `brand-primary` become `brandPrimary`, `blue.500`
/// becomes `blue500`. Returns `null` if the result is not an identifier.
String? camelCaseName(String relativePath) {
  final words = [
    for (final segment in relativePath.split('.'))
      for (final word in segment.split(RegExp(r'[-_\s]+')))
        if (word.isNotEmpty) word,
  ];
  if (words.isEmpty) return null;
  final buffer = StringBuffer(
    words.first[0].toLowerCase() + words.first.substring(1),
  );
  for (final word in words.skip(1)) {
    buffer.write(word[0].toUpperCase() + word.substring(1));
  }
  final name = buffer.toString();
  return RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name) ? name : null;
}

const _numberCategories = {
  DesignCategory.spacing,
  DesignCategory.radius,
  DesignCategory.iconSize,
  DesignCategory.elevation,
};

/// The value of [token] as a Dart token of [category].
///
/// Throws a [FormatException] whose message says why the token cannot be
/// compared: a type that does not fit the category, a unit or color space
/// that is not supported, or a malformed value.
TokenValue designValueOf(DesignCategory category, DesignToken token) {
  final type = token.type;
  final value = token.value;
  if (category == DesignCategory.color) {
    _expectType(type, const {'color'}, category);
    return ColorValue(_color(value));
  }
  if (_numberCategories.contains(category)) {
    _expectType(type, const {'dimension', 'number'}, category);
    return NumberValue(
      type == 'number' ? _number(value, 'value') : _pixels(value, 'value'),
    );
  }
  if (category == DesignCategory.typography) {
    _expectType(type, const {'typography'}, category);
    final map = _object(value, 'value');
    return TextStyleValue(
      fontSize: map['fontSize'] == null
          ? null
          : _pixels(map['fontSize'], 'fontSize'),
      fontWeight: map['fontWeight'] == null
          ? null
          : _fontWeight(map['fontWeight']),
      height: map['lineHeight'] == null
          ? null
          : _number(map['lineHeight'], 'lineHeight'),
      letterSpacing: map['letterSpacing'] == null
          ? null
          : _pixels(map['letterSpacing'], 'letterSpacing'),
    );
  }
  if (category == DesignCategory.shadow) {
    _expectType(type, const {'shadow'}, category);
    final layers = value is List<Object?> ? value : [value];
    return ShadowValue([
      for (final layer in layers) _shadowLayer(layer),
    ], isList: value is List<Object?>);
  }
  throw FormatException('${category.key} tokens cannot be compared');
}

void _expectType(String? type, Set<String> allowed, DesignCategory category) {
  if (type == null) {
    throw const FormatException(r'the token has no $type');
  }
  if (!allowed.contains(type)) {
    throw FormatException(
      'a $type token cannot be compared with ${category.key} tokens '
      '(expected ${allowed.join(' or ')})',
    );
  }
}

Map<String, Object?> _object(Object? value, String what) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$what is not an object');
}

double _number(Object? value, String what) {
  if (value is num) return value.toDouble();
  throw FormatException('$what is not a number');
}

double _pixels(Object? value, String what) {
  final map = _object(value, what);
  final unit = map['unit'];
  if (unit != 'px') {
    throw FormatException(
      '$what is in "$unit"; only px dimensions can be compared',
    );
  }
  return _number(map['value'], '$what value');
}

const _fontWeights = {
  'thin': 100,
  'hairline': 100,
  'extra-light': 200,
  'ultra-light': 200,
  'light': 300,
  'normal': 400,
  'regular': 400,
  'book': 400,
  'medium': 500,
  'semi-bold': 600,
  'demi-bold': 600,
  'bold': 700,
  'extra-bold': 800,
  'ultra-bold': 800,
  'black': 900,
  'heavy': 900,
  'extra-black': 950,
  'ultra-black': 950,
};

int _fontWeight(Object? value) {
  if (value is num) return value.round();
  final named = _fontWeights[value];
  if (named != null) return named;
  throw FormatException('fontWeight "$value" is not a weight');
}

int _channel(Object? value, String what) {
  final number = value == 'none' ? 0.0 : _number(value, what);
  if (number < 0 || number > 1) {
    throw FormatException('$what $number is outside 0 to 1');
  }
  return (number * 255).round();
}

final _hex = RegExp(r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$');

/// An ARGB value from a color object (`srgb` components, or the `hex`
/// fallback of another color space), or from a `#RRGGBB` / `#RRGGBBAA`
/// string as older exporters write.
int _color(Object? value) {
  if (value is String) {
    final match = _hex.firstMatch(value);
    if (match == null) throw FormatException('"$value" is not a color');
    final rgb = int.parse(match.group(1)!, radix: 16);
    final alpha = match.group(2) == null
        ? 0xFF
        : int.parse(match.group(2)!, radix: 16);
    return (alpha << 24) | rgb;
  }
  final map = _object(value, 'color');
  final alphaValue = map['alpha'];
  final alpha = alphaValue == null ? 0xFF : _channel(alphaValue, 'alpha');
  final space = map['colorSpace'];
  final components = map['components'];
  if (space == 'srgb' &&
      components is List<Object?> &&
      components.length == 3) {
    final r = _channel(components[0], 'red');
    final g = _channel(components[1], 'green');
    final b = _channel(components[2], 'blue');
    return (alpha << 24) | (r << 16) | (g << 8) | b;
  }
  final hex = map['hex'];
  if (hex is String) {
    final match = _hex.firstMatch(hex);
    if (match != null && match.group(2) == null) {
      return (alpha << 24) | int.parse(match.group(1)!, radix: 16);
    }
  }
  throw FormatException(
    'the color space "$space" can only be compared through a "hex" fallback',
  );
}

ShadowLayer _shadowLayer(Object? value) {
  final map = _object(value, 'shadow');
  if (map['inset'] == true) {
    throw const FormatException('inset shadows have no Flutter BoxShadow');
  }
  return ShadowLayer(
    color: _color(map['color']),
    blurRadius: _pixels(map['blur'], 'blur'),
    spreadRadius: _pixels(map['spread'], 'spread'),
    dx: _pixels(map['offsetX'], 'offsetX'),
    dy: _pixels(map['offsetY'], 'offsetY'),
  );
}

/// Whether a Dart token value and a design value are the same.
///
/// A radius token compares by its number whether it is a `double`, a
/// `Radius` or a `BorderRadius`; a shadow compares by its layers.
bool sameValue(TokenValue dart, TokenValue design) {
  double? numberOf(TokenValue value) => switch (value) {
    NumberValue(:final value) => value,
    RadiusValue(:final value) => value,
    BorderRadiusValue(:final value) => value,
    _ => null,
  };
  final a = numberOf(dart);
  final b = numberOf(design);
  if (a != null || b != null) {
    return a != null && b != null && (a - b).abs() < 1e-9;
  }
  if (dart is ShadowValue && design is ShadowValue) {
    if (dart.layers.length != design.layers.length) return false;
    for (var i = 0; i < dart.layers.length; i++) {
      if (dart.layers[i] != design.layers[i]) return false;
    }
    return true;
  }
  return dart == design;
}

String _num(double value) =>
    value == value.truncateToDouble() ? '${value.toInt()}' : '$value';

String _argb(int argb) =>
    '0x${argb.toRadixString(16).toUpperCase().padLeft(8, '0')}';

/// [value] as a short text for reports.
String describeValue(TokenValue value) => switch (value) {
  NumberValue(:final value) => _num(value),
  RadiusValue(:final value) => _num(value),
  BorderRadiusValue(:final value) => _num(value),
  ColorValue(:final argb) => _argb(argb),
  TextStyleValue() => [
    if (value.fontSize != null) 'fontSize ${_num(value.fontSize!)}',
    if (value.fontWeight != null) 'fontWeight ${value.fontWeight}',
    if (value.height != null) 'height ${_num(value.height!)}',
    if (value.letterSpacing != null)
      'letterSpacing ${_num(value.letterSpacing!)}',
  ].join(', '),
  ShadowValue(:final layers) =>
    layers
        .map(
          (l) =>
              '${_argb(l.color)} blur ${_num(l.blurRadius)} spread '
              '${_num(l.spreadRadius)} offset (${_num(l.dx)}, ${_num(l.dy)})',
        )
        .join('; '),
};
