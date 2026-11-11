import 'color_math.dart';

/// A candidate token that is close to, or equal to, a raw value.
final class TokenMatch<T> {
  /// Creates a match.
  const TokenMatch(this.item, this.distance);

  /// The matching candidate.
  final T item;

  /// `0` for an exact match, otherwise the numeric difference or the CIEDE2000
  /// color difference.
  final double distance;

  /// Whether the match is exact.
  bool get isExact => distance == 0;
}

/// Finds the tokens closest to a raw value.
///
/// Numeric matching is by absolute difference; color matching is by CIEDE2000
/// through CIE L*a*b* and requires equal alpha.
final class NearestTokenMatcher {
  const NearestTokenMatcher._();

  /// The default number of "nearest" candidates offered.
  static const int defaultLimit = 3;

  static const double _epsilon = 1e-9;

  /// Returns the candidates within [tolerance] of [value], closest first.
  ///
  /// Exact matches come first. Candidates at the same distance are all kept,
  /// so ties are offered together; at most [limit] distinct distances are
  /// returned for the non-exact part.
  static List<TokenMatch<T>> matchNumber<T>(
    double value,
    Iterable<T> candidates,
    double Function(T) valueOf, {
    double tolerance = 0,
    int limit = defaultLimit,
  }) {
    final matches = <TokenMatch<T>>[];
    for (final candidate in candidates) {
      final distance = (valueOf(candidate) - value).abs();
      if (distance <= _epsilon) {
        matches.add(TokenMatch(candidate, 0));
      } else if (distance <= tolerance + _epsilon) {
        matches.add(TokenMatch(candidate, distance));
      }
    }
    return _order(matches, limit);
  }

  /// Returns the candidates equal to, or within [maxDeltaE] of, [argb].
  ///
  /// A candidate with a different alpha channel is never a match. A
  /// [maxDeltaE] of `0` allows exact matches only.
  static List<TokenMatch<T>> matchColor<T>(
    int argb,
    Iterable<T> candidates,
    int Function(T) argbOf, {
    double maxDeltaE = 0,
    int limit = defaultLimit,
  }) {
    final target = argb & 0xFFFFFFFF;
    final lab = Lab.fromArgb(target);
    final matches = <TokenMatch<T>>[];
    for (final candidate in candidates) {
      final other = argbOf(candidate) & 0xFFFFFFFF;
      if (other == target) {
        matches.add(TokenMatch(candidate, 0));
        continue;
      }
      if (maxDeltaE <= 0 || (other >> 24) != (target >> 24)) continue;
      final distance = ciede2000(lab, Lab.fromArgb(other));
      if (distance <= maxDeltaE) {
        matches.add(TokenMatch(candidate, distance));
      }
    }
    return _order(matches, limit);
  }

  static List<TokenMatch<T>> _order<T>(List<TokenMatch<T>> matches, int limit) {
    final exact = matches.where((m) => m.isExact).toList();
    final near = matches.where((m) => !m.isExact).toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    final result = <TokenMatch<T>>[...exact];
    var distinct = 0;
    double? last;
    for (final match in near) {
      if (last == null || (match.distance - last).abs() > _epsilon) {
        distinct++;
        last = match.distance;
      }
      if (distinct > limit) break;
      result.add(match);
    }
    return result;
  }
}
