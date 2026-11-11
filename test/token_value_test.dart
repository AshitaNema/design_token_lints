import 'package:design_token_lints/src/tokens/token_value.dart';
import 'package:test/test.dart';

void main() {
  test('values compare by content', () {
    expect(const NumberValue(4), const NumberValue(4));
    expect(const NumberValue(4), isNot(const NumberValue(5)));
    expect(const ColorValue(0xFF000000), const ColorValue(0xFF000000));
    expect(const RadiusValue(8), const RadiusValue(8));
    expect(const RadiusValue(8), isNot(const BorderRadiusValue(8)));
    expect(const BorderRadiusValue(8), const BorderRadiusValue(8));
    expect(
      const TextStyleValue(fontSize: 12, fontWeight: 400),
      const TextStyleValue(fontSize: 12, fontWeight: 400),
    );
    expect(
      const TextStyleValue(fontSize: 12, fontWeight: 400),
      isNot(const TextStyleValue(fontSize: 12, fontWeight: 700)),
    );
    expect(
      const ShadowValue([ShadowLayer(color: 1, blurRadius: 2)], isList: true),
      const ShadowValue([ShadowLayer(color: 1, blurRadius: 2)], isList: true),
    );
    expect(
      const ShadowValue([ShadowLayer(color: 1)], isList: true),
      isNot(const ShadowValue([ShadowLayer(color: 1)], isList: false)),
    );
    expect(
      const ShadowValue([ShadowLayer(color: 1)], isList: true),
      isNot(const ShadowValue([ShadowLayer(color: 2)], isList: true)),
    );
    expect(
      const ShadowValue([ShadowLayer(color: 1)], isList: true),
      isNot(const ShadowValue([], isList: true)),
    );
  });

  test('equal values have equal hash codes', () {
    expect(const NumberValue(4).hashCode, const NumberValue(4).hashCode);
    expect(const ColorValue(7).hashCode, const ColorValue(7).hashCode);
    expect(const RadiusValue(2).hashCode, const RadiusValue(2).hashCode);
    expect(
      const BorderRadiusValue(2).hashCode,
      const BorderRadiusValue(2).hashCode,
    );
    expect(
      const TextStyleValue(fontSize: 1).hashCode,
      const TextStyleValue(fontSize: 1).hashCode,
    );
    expect(
      const ShadowLayer(color: 1, dx: 2).hashCode,
      const ShadowLayer(color: 1, dx: 2).hashCode,
    );
    expect(
      const ShadowValue([ShadowLayer(color: 1)], isList: false).hashCode,
      const ShadowValue([ShadowLayer(color: 1)], isList: false).hashCode,
    );
  });

  test('values describe themselves', () {
    expect(const NumberValue(4).toString(), contains('4'));
    expect(const ColorValue(0xFF1E88E5).toString(), contains('FF1E88E5'));
    expect(const RadiusValue(8).toString(), contains('8'));
    expect(const BorderRadiusValue(8).toString(), contains('8'));
    expect(
      const TextStyleValue(fontSize: 12).toString(),
      contains('fontSize: 12'),
    );
    expect(const ShadowLayer(color: 1).toString(), contains('blur'));
    expect(
      const ShadowValue([ShadowLayer(color: 1)], isList: true).toString(),
      contains('isList: true'),
    );
  });
}
