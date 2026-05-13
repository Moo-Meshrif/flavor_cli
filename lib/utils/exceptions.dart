class CliException implements Exception {
  final String message;
  final bool isLogged;

  CliException(this.message, {this.isLogged = false});

  @override
  String toString() => message;
}
