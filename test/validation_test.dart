import 'package:test/test.dart';
import 'package:flavor_cli/src/utils/validation.dart';

void main() {
  group('ValidationUtils', () {
    test('isValidIdentifier accepts valid Dart identifiers', () {
      expect(ValidationUtils.isValidIdentifier('dev'), isTrue);
      expect(ValidationUtils.isValidIdentifier('prod'), isTrue);
      expect(ValidationUtils.isValidIdentifier('flavor_1'), isTrue);
      expect(ValidationUtils.isValidIdentifier('_internal'), isTrue);
      expect(ValidationUtils.isValidIdentifier('mySpecialFlavor'), isTrue);
    });

    test('isValidIdentifier rejects names starting with numbers', () {
      expect(ValidationUtils.isValidIdentifier('1'), isFalse);
      expect(ValidationUtils.isValidIdentifier('1dev'), isFalse);
      expect(ValidationUtils.isValidIdentifier('24prod'), isFalse);
    });

    test('isValidIdentifier rejects names with spaces or special characters', () {
      expect(ValidationUtils.isValidIdentifier('dev prod'), isFalse);
      expect(ValidationUtils.isValidIdentifier('staging-flavor'), isFalse);
      expect(ValidationUtils.isValidIdentifier('flavor!'), isFalse);
      expect(ValidationUtils.isValidIdentifier('prod@home'), isFalse);
    });

    test('isValidIdentifier rejects empty strings', () {
      expect(ValidationUtils.isValidIdentifier(''), isFalse);
    });

    test('isValidIdentifier rejects Dart reserved keywords', () {
      expect(ValidationUtils.isValidIdentifier('class'), isFalse);
      expect(ValidationUtils.isValidIdentifier('enum'), isFalse);
      expect(ValidationUtils.isValidIdentifier('void'), isFalse);
      expect(ValidationUtils.isValidIdentifier('switch'), isFalse);
      expect(ValidationUtils.isValidIdentifier('null'), isFalse);
      expect(ValidationUtils.isValidIdentifier('true'), isFalse);
      expect(ValidationUtils.isValidIdentifier('false'), isFalse);
    });
  });
}
