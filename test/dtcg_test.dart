import 'package:design_token_lints/src/design_tokens/dtcg.dart';
import 'package:test/test.dart';

void main() {
  Map<String, DesignToken> tokens(String json) {
    final file = DesignTokenFile.parse(json);
    expect(file.problems, isEmpty);
    return {for (final t in file.tokens) t.name: t};
  }

  List<String> problems(String json) => [
    for (final p in DesignTokenFile.parse(json).problems) '$p',
  ];

  group('structure', () {
    test(r'groups, tokens and inherited $type', () {
      final t = tokens(r'''
{
  "color": {
    "$type": "color",
    "$description": "Brand colors",
    "brand": { "primary": { "$value": "#112233" } },
    "text": { "$type": "number", "$value": 1 }
  },
  "untyped": { "$value": 3 }
}''');
      expect(t.keys, ['color.brand.primary', 'color.text', 'untyped']);
      expect(t['color.brand.primary']!.type, 'color');
      expect(t['color.brand.primary']!.path, ['color', 'brand', 'primary']);
      expect(t['color.text']!.type, 'number');
      expect(t['untyped']!.type, isNull);
    });

    test(r'$root is the group'
        's own token', () {
      final t = tokens(
        r'''
{ "accent": { "$type": "number", "$root": { "$value": 1 }, "light": { "$value": 2 } } }''',
      );
      expect(t.keys, ['accent', 'accent.light']);
    });

    test('under() keys tokens by their path in the group', () {
      final file = DesignTokenFile.parse(r'''
{ "color": { "$type": "color", "a": { "$value": "#000000" }, "b": { "c": { "$value": "#ffffff" } } },
  "colorful": { "$value": 1 } }''');
      expect(file.under('color').keys, ['a', 'b.c']);
      expect(file.under('color.b').keys, ['c']);
      expect(file.under('').keys, ['color.a', 'color.b.c', 'colorful']);
    });

    test(r'$extends is reported and ignored', () {
      expect(
        problems(r'''
{ "base": { "a": { "$value": 1 } },
  "more": { "$extends": "{base}", "b": { "$value": 2 } } }'''),
        [r'more: $extends is not supported; the group is read without it'],
      );
    });

    test('invalid files', () {
      expect(problems('{'), [startsWith('not valid JSON')]);
      expect(problems('[1]'), ['the file must be a JSON object']);
    });
  });

  group('references', () {
    test('aliases, also chained, and their type', () {
      final t = tokens(r'''
{
  "base": { "$type": "color", "blue": { "$value": "#0000ff" } },
  "brand": { "primary": { "$value": "{base.blue}" }, "link": { "$value": "{brand.primary}" } }
}''');
      expect(t['brand.link']!.value, '#0000ff');
      expect(t['brand.link']!.type, 'color');
    });

    test('aliases inside composite values', () {
      final t = tokens(r'''
{
  "size": { "$type": "dimension", "s": { "$value": { "value": 2, "unit": "px" } } },
  "shadow": { "$type": "shadow", "card": { "$value": { "blur": "{size.s}" } } }
}''');
      expect(t['shadow.card']!.value, {
        'blur': {'value': 2, 'unit': 'px'},
      });
    });

    test(r'$ref JSON pointers, with escapes and array indexes', () {
      final t = tokens(r'''
{
  "a/b": { "c~d": { "$type": "number", "$value": [5, 6] } },
  "copy": { "$type": "number", "$value": { "$ref": "#/a~1b/c~0d/$value/1" } },
  "whole": { "$ref": "#/a~1b/c~0d/$value", "$type": "number" }
}''');
      expect(t['copy']!.value, 6);
      expect(t['whole']!.value, [5, 6]);
    });

    test('circular references are reported', () {
      expect(
        problems(r'''
{ "a": { "$value": "{b}" }, "b": { "$value": "{a}" } }'''),
        [
          'a: circular reference through {a}',
          'b: circular reference through {b}',
        ],
      );
      expect(
        problems(r'''
{ "a": { "$value": { "$ref": "#/a/$value" } } }'''),
        [r'a: circular reference through #/a/$value'],
      );
    });

    test('references that point nowhere are reported', () {
      expect(
        problems(r'''
{ "a": { "$value": "{missing.token}" },
  "b": { "$value": { "$ref": "#/nothing/here" } },
  "c": { "$value": { "$ref": "#/b/$value/9" } },
  "d": { "$value": { "$ref": "other.json#/x" } } }'''),
        [
          'a: the reference {missing.token} does not name a token',
          'b: the reference #/nothing/here points nowhere',
          r'c: the reference #/b/$value/9 points nowhere',
          r'd: only $ref pointers within the file are supported',
        ],
      );
    });

    test('a string that is not a whole alias is kept as text', () {
      final t = tokens(r'{ "a": { "$value": "{not} an alias" } }');
      expect(t['a']!.value, '{not} an alias');
    });
  });
}
