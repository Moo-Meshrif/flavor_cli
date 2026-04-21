import 'package:test/test.dart';
import 'package:flavor_cli/utils/validation.dart';

void main() {
  group('ValidationUtils', () {
    test('isValidIdentifier should validate correct identifiers', () {
      expect(ValidationUtils.isValidIdentifier('myVar'), isTrue);
      expect(ValidationUtils.isValidIdentifier('_private'), isTrue);
      expect(ValidationUtils.isValidIdentifier('v1'), isTrue);
    });

    test('isValidIdentifier should reject invalid identifiers', () {
      expect(ValidationUtils.isValidIdentifier('1var'), isFalse);
      expect(ValidationUtils.isValidIdentifier('my-var'), isFalse);
      expect(ValidationUtils.isValidIdentifier('my var'), isFalse);
      expect(ValidationUtils.isValidIdentifier(''), isFalse);
    });

    test('isValidIdentifier should reject reserved keywords', () {
      expect(ValidationUtils.isValidIdentifier('class'), isFalse);
      expect(ValidationUtils.isValidIdentifier('void'), isFalse);
      expect(ValidationUtils.isValidIdentifier('if'), isFalse);
    });

    test('hasArabic should detect Arabic characters', () {
      expect(ValidationUtils.hasArabic('Hello'), isFalse);
      expect(ValidationUtils.hasArabic('مرحبا'), isTrue);
      expect(ValidationUtils.hasArabic('Hello مرحبا'), isTrue);
    });
  });
}
