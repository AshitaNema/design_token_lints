import 'package:analyzer/dart/element/element.dart';

/// The packages that declare Flutter's own classes.
///
/// Since Flutter 3.47 the Material and Cupertino libraries are also published
/// as the `material_ui` and `cupertino_ui` packages, which declare their own
/// `Colors`, `ElevatedButton` and so on rather than re-exporting Flutter's.
const frameworkPackages = {'flutter', 'material_ui', 'cupertino_ui'};

/// Whether [element] is declared in Flutter or in one of its Material and
/// Cupertino packages.
bool isDeclaredInFlutter(Element? element) {
  final library = element?.library;
  if (library == null) return false;
  final uri = library.uri;
  return uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      frameworkPackages.contains(uri.pathSegments.first);
}
