import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

import '../config/rule_id.dart';

/// The `// ignore:` and `// ignore_for_file:` comments of a file, read the way
/// the analysis server reads them.
///
/// The analysis server hides ignored plugin diagnostics on its own; the
/// command line tool walks the code directly and needs this to do the same.
/// A comment on a line of its own applies to the next line, a comment after
/// code applies to its own line, and plugin rules are named
/// `design_token_lints/<rule>`.
final class IgnoreComments {
  IgnoreComments._(this._lineInfo, this._onLine, this._forFile);

  /// Reads the ignore comments of [unit].
  factory IgnoreComments.of(CompilationUnit unit, String content) {
    final lineInfo = unit.lineInfo;
    final onLine = <int, Set<String>>{};
    final forFile = <String>{};
    for (Token? token = unit.beginToken; token != null; token = token.next) {
      for (
        Token? comment = token.precedingComments;
        comment != null;
        comment = comment.next
      ) {
        final match = _pattern.firstMatch(comment.lexeme);
        if (match == null) continue;
        final names = {
          for (final name in match.group(2)!.split(','))
            if (name.trim().isNotEmpty) name.trim().toLowerCase(),
        };
        if (match.group(1) != null) {
          forFile.addAll(names);
          continue;
        }
        final location = lineInfo.getLocation(comment.offset);
        var line = location.lineNumber;
        final lineStart = lineInfo.getOffsetOfLine(line - 1);
        if (content.substring(lineStart, comment.offset).trim().isEmpty) {
          line++;
        }
        onLine.putIfAbsent(line, () => {}).addAll(names);
      }
      if (token.isEof || token.next == token) break;
    }
    return IgnoreComments._(lineInfo, onLine, forFile);
  }

  static final _pattern = RegExp(r'^//\s*ignore(_for_file)?\s*:(.*)$');

  final LineInfo _lineInfo;
  final Map<int, Set<String>> _onLine;
  final Set<String> _forFile;

  /// Whether a diagnostic of [rule] starting at [offset] is ignored.
  bool ignores(RuleId rule, int offset) {
    final name = 'design_token_lints/${rule.code}';
    if (_forFile.contains(name)) return true;
    final line = _lineInfo.getLocation(offset).lineNumber;
    return _onLine[line]?.contains(name) ?? false;
  }
}
