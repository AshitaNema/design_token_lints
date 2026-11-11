import 'package:analyzer/dart/ast/ast.dart';

import '../tokens/nearest_token_matcher.dart';
import '../tokens/token_index.dart';
import '../tokens/token_value.dart';
import 'finding.dart';

/// Suggestions for a numeric [literal] among the number-valued [entries].
///
/// The literal is replaced by the token reference, so a surrounding
/// constructor such as `Radius.circular(...)` stays in place.
List<TokenSuggestion> numberSuggestions({
  required Iterable<TokenEntry> entries,
  required AstNode literal,
  required double value,
  required double tolerance,
}) {
  final numbers = [
    for (final entry in entries)
      if (entry.value is NumberValue) entry,
  ];
  final matches = NearestTokenMatcher.matchNumber<TokenEntry>(
    value,
    numbers,
    (entry) => (entry.value as NumberValue).value,
    tolerance: tolerance,
  );
  return [
    for (final match in matches)
      TokenSuggestion(
        entry: match.item,
        distance: match.distance,
        offset: literal.offset,
        length: literal.length,
        replacement: match.item.reference,
        importUri: match.item.importUri,
      ),
  ];
}

/// Returns the value of a non-negative numeric literal, or `null`.
double? literalValue(AstNode? node) {
  if (node is IntegerLiteral) return node.value?.toDouble();
  if (node is DoubleLiteral) return node.value;
  return null;
}
