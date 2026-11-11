import 'package:design_token_lints/src/tokens/color_math.dart';
import 'package:design_token_lints/src/tokens/nearest_token_matcher.dart';
import 'package:test/test.dart';

void main() {
  group('matchNumber', () {
    const candidates = [4.0, 8.0, 16.0, 24.0, 32.0];
    List<TokenMatch<double>> match(
      double value, {
      double tolerance = 0,
      int limit = 3,
    }) => NearestTokenMatcher.matchNumber<double>(
      value,
      candidates,
      (c) => c,
      tolerance: tolerance,
      limit: limit,
    );

    test('finds an exact match', () {
      final result = match(16);
      expect(result.map((m) => m.item), [16.0]);
      expect(result.single.isExact, isTrue);
    });

    test('finds nothing without tolerance', () {
      expect(match(15), isEmpty);
    });

    test('respects the tolerance boundary', () {
      expect(match(15, tolerance: 1).map((m) => m.item), [16.0]);
      expect(match(14, tolerance: 1), isEmpty);
      expect(match(14, tolerance: 2).map((m) => m.item), [16.0]);
    });

    test('orders by distance', () {
      final result = match(7, tolerance: 20);
      expect(result.map((m) => m.item), [8.0, 4.0, 16.0]);
      expect(result.map((m) => m.distance), [1.0, 3.0, 9.0]);
    });

    test('keeps candidates at the same distance together', () {
      final result = match(6, tolerance: 2);
      expect(result.map((m) => m.item), [4.0, 8.0]);
      expect(result.map((m) => m.distance), [2.0, 2.0]);
    });

    test('limits the number of distinct distances', () {
      final result = match(20, tolerance: 20, limit: 2);
      expect(result.map((m) => m.item), [16.0, 24.0, 8.0, 32.0]);
      expect(result.map((m) => m.distance).toSet().length, 2);
    });

    test('lists exact matches before near ones', () {
      final result = NearestTokenMatcher.matchNumber<double>(
        16,
        const [15.0, 16.0, 17.0],
        (c) => c,
        tolerance: 1,
      );
      expect(result.first.item, 16.0);
      expect(result.first.isExact, isTrue);
      expect(result.skip(1).map((m) => m.item), [15.0, 17.0]);
    });

    test('treats floating point noise as exact', () {
      final result = NearestTokenMatcher.matchNumber<double>(0.1 + 0.2, const [
        0.3,
      ], (c) => c);
      expect(result.single.isExact, isTrue);
    });

    test('keeps duplicates of an exact value', () {
      final result = NearestTokenMatcher.matchNumber<String>(16, const [
        'md',
        'doubleSm',
      ], (c) => 16);
      expect(result.map((m) => m.item), ['md', 'doubleSm']);
    });
  });

  group('matchColor', () {
    const primary = 0xFF1E88E5;
    const candidates = [primary, 0xFF1565C0, 0xFFFFFFFF, 0x801E88E5];
    List<TokenMatch<int>> match(int argb, {double deltaE = 0}) =>
        NearestTokenMatcher.matchColor<int>(
          argb,
          candidates,
          (c) => c,
          maxDeltaE: deltaE,
        );

    test('finds an exact match', () {
      expect(match(primary).map((m) => m.item), [primary]);
    });

    test('finds nothing near without a threshold', () {
      expect(match(0xFF1E88E6), isEmpty);
    });

    test('finds a near match within the threshold', () {
      final result = match(0xFF1E88E6, deltaE: 2);
      expect(result.map((m) => m.item), [primary]);
      expect(result.single.distance, inInclusiveRange(0.001, 0.5));
    });

    test('excludes colors beyond the threshold', () {
      expect(match(0xFFFF0000, deltaE: 2), isEmpty);
    });

    test('never matches a different alpha', () {
      final result = match(0x801E88E6, deltaE: 100);
      expect(result.map((m) => m.item), [0x801E88E5]);
    });

    test('orders candidates by distance and limits them', () {
      final result = NearestTokenMatcher.matchColor<int>(
        0xFF202020,
        const [0xFF222222, 0xFF282828, 0xFF303030, 0xFF404040, 0xFF505050],
        (c) => c,
        maxDeltaE: 100,
      );
      expect(result.length, 3);
      final distances = result.map((m) => m.distance).toList();
      expect(distances, [...distances]..sort());
    });
  });

  group('ciede2000', () {
    // Reference pairs from Sharma, Wu and Dalal (2005).
    const pairs = [
      (Lab(50, 2.6772, -79.7751), Lab(50, 0, -82.7485), 2.0425),
      (Lab(50, 3.1571, -77.2803), Lab(50, 0, -82.7485), 2.8615),
      (Lab(50, 2.8361, -74.0200), Lab(50, 0, -82.7485), 3.4412),
      (Lab(50, -1.3802, -84.2814), Lab(50, 0, -82.7485), 1.0000),
      (Lab(50, 2.5, 0), Lab(50, 0, -2.5), 4.3065),
      (Lab(50, 2.5, 0), Lab(73, 25, -18), 27.1492),
      (
        Lab(60.2574, -34.0099, 36.2677),
        Lab(60.4626, -34.1751, 39.4387),
        1.2644,
      ),
      (Lab(2.0776, 0.0795, -1.1350), Lab(0.9033, -0.0636, -0.5514), 0.9082),
    ];

    for (final (a, b, expected) in pairs) {
      test('${a.l},${a.a},${a.b} vs ${b.l},${b.a},${b.b}', () {
        expect(ciede2000(a, b), closeTo(expected, 1e-3));
        expect(ciede2000(b, a), closeTo(expected, 1e-3));
      });
    }

    test('identical colors have no difference', () {
      expect(ciede2000(const Lab(50, 10, 10), const Lab(50, 10, 10)), 0);
    });
  });

  group('Lab.fromArgb', () {
    test('white', () {
      final lab = Lab.fromArgb(0xFFFFFFFF);
      expect(lab.l, closeTo(100, 0.01));
      expect(lab.a, closeTo(0, 0.01));
      expect(lab.b, closeTo(0, 0.01));
    });

    test('black', () {
      expect(Lab.fromArgb(0xFF000000).l, closeTo(0, 0.01));
    });

    test('red', () {
      final lab = Lab.fromArgb(0xFFFF0000);
      expect(lab.l, closeTo(53.24, 0.05));
      expect(lab.a, closeTo(80.09, 0.05));
      expect(lab.b, closeTo(67.20, 0.05));
    });

    test('ignores alpha', () {
      final opaque = Lab.fromArgb(0xFF1E88E5);
      final faded = Lab.fromArgb(0x101E88E5);
      expect(faded.l, opaque.l);
    });
  });
}
