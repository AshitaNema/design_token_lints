import 'package:analyzer/dart/element/element.dart';

/// Whether [element] is declared in the Flutter framework.
bool isDeclaredInFlutter(Element? element) {
  final library = element?.library;
  if (library == null) return false;
  final uri = library.uri;
  return uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == 'flutter';
}
