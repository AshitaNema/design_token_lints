// Regenerates lib/src/tokens/material_colors.dart from Flutter's
// `Colors` class.
//
// Usage: dart run tool/generate_material_colors.dart <flutter-sdk-root>
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/generate_material_colors.dart <flutter-sdk-root>',
    );
    exitCode = 64;
    return;
  }
  final root = args.single;
  final source = File(
    '$root/packages/flutter/lib/src/material/colors.dart',
  ).readAsStringSync();
  final versionFile = File('$root/bin/cache/flutter.version.json');
  final version = versionFile.existsSync()
      ? RegExp(
              r'"frameworkVersion":\s*"([^"]+)"',
            ).firstMatch(versionFile.readAsStringSync())?.group(1) ??
            'unknown'
      : 'unknown';

  final values = <String, int>{};

  final plain = RegExp(
    r'static const Color (\w+) = Color\(0x([0-9A-Fa-f]{8})\);',
  );
  for (final m in plain.allMatches(source)) {
    values[m.group(1)!] = int.parse(m.group(2)!, radix: 16);
  }

  final constants = <String, int>{};
  for (final m in RegExp(
    r'static const int (_\w+) = 0x([0-9A-Fa-f]{8});',
  ).allMatches(source)) {
    constants[m.group(1)!] = int.parse(m.group(2)!, radix: 16);
  }

  final swatch = RegExp(
    r'static const (MaterialColor|MaterialAccentColor)\s+(\w+)\s*=\s*'
    r'Material(?:Accent)?Color\(\s*(\w+),\s*<int, Color>\{(.*?)\}\s*\);',
    dotAll: true,
  );
  for (final m in swatch.allMatches(source)) {
    final name = m.group(2)!;
    final primaryRef = m.group(3)!;
    final body = m.group(4)!;
    final primary = constants[primaryRef];
    if (primary == null) {
      throw StateError('No primary value for $name ($primaryRef)');
    }
    values[name] = primary;
    final shade = RegExp(r'(\d+):\s*Color\((0x[0-9A-Fa-f]{8}|\w+)\)');
    for (final s in shade.allMatches(body)) {
      final ref = s.group(2)!;
      final value = ref.startsWith('0x')
          ? int.parse(ref.substring(2), radix: 16)
          : primary;
      values['$name.${s.group(1)}'] = value;
    }
  }

  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final out = StringBuffer()
    ..writeln('// Values of Flutter\'s `Colors` palette, keyed by member path.')
    ..writeln('// Regenerate with tool/generate_material_colors.dart.')
    ..writeln('// Source: Flutter $version.')
    ..writeln()
    ..writeln('/// ARGB values of the members of Flutter\'s `Colors` class.')
    ..writeln('///')
    ..writeln('/// Keys are `name` for plain colors and swatch primaries')
    ..writeln('/// (`red`, `black87`) and `name.shade` for swatch shades')
    ..writeln('/// (`red.100`, `redAccent.200`).')
    ..writeln('const Map<String, int> materialColorValues = <String, int>{');
  for (final e in entries) {
    final hex = e.value.toRadixString(16).toUpperCase().padLeft(8, '0');
    out.writeln("  '${e.key}': 0x$hex,");
  }
  out.writeln('};');
  File('lib/src/tokens/material_colors.dart').writeAsStringSync(out.toString());
  stdout.writeln('Wrote ${entries.length} entries from Flutter $version.');
}
