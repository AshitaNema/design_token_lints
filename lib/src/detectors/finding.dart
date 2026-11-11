import 'package:analyzer/dart/ast/ast.dart';

import '../config/rule_id.dart';
import '../tokens/token_index.dart';

/// A replacement that would bring a [Finding] back into the design system.
final class TokenSuggestion {
  /// Creates a suggestion.
  const TokenSuggestion({
    required this.entry,
    required this.distance,
    required this.offset,
    required this.length,
    required this.replacement,
    this.importUri,
  });

  /// The token that is suggested.
  final TokenEntry entry;

  /// `0` for an exact match, otherwise the numeric or CIEDE2000 distance.
  final double distance;

  /// The offset of the text to replace.
  final int offset;

  /// The length of the text to replace.
  final int length;

  /// The text that replaces the range.
  final String replacement;

  /// The library that must be imported for [replacement] to resolve.
  final String? importUri;

  /// Whether the match is exact.
  bool get isExact => distance == 0;

  /// The source reference of the suggested token.
  String get reference => entry.reference;
}

/// A place in the code that bypasses the design system.
final class Finding {
  /// Creates a finding.
  Finding({
    required this.rule,
    required this.node,
    required this.raw,
    this.suggestions = const [],
    this.fallbackTokenClass,
  });

  /// The rule that produced the finding.
  final RuleId rule;

  /// The narrowest node to report at.
  final AstNode node;

  /// The offending source text, as shown in messages.
  final String raw;

  /// Replacements, exact ones first, then nearest ones by distance.
  final List<TokenSuggestion> suggestions;

  /// The token class named in messages when there is no suggestion.
  final String? fallbackTokenClass;

  /// The offset of the report range.
  int get offset => node.offset;

  /// The length of the report range.
  int get length => node.length;

  /// The best suggestion, if any.
  TokenSuggestion? get best => suggestions.isEmpty ? null : suggestions.first;

  /// The exact suggestions.
  List<TokenSuggestion> get exact => [
    for (final s in suggestions)
      if (s.isExact) s,
  ];

  /// The nearest (non-exact) suggestions, closest first.
  List<TokenSuggestion> get nearest => [
    for (final s in suggestions)
      if (!s.isExact) s,
  ];

  /// The token named in the correction message.
  String get suggestedToken {
    final suggestion = best;
    if (suggestion == null) {
      return fallbackTokenClass == null
          ? 'a design-system token'
          : 'a token from $fallbackTokenClass';
    }
    return suggestion.isExact
        ? suggestion.reference
        : '${suggestion.reference} (nearest match)';
  }

  /// The arguments for the rule's problem and correction messages.
  List<Object> get messageArguments => [raw, suggestedToken];
}
