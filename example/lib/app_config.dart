// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:flutter_dotenv/flutter_dotenv.dart';

enum Flavor { dev, stage, prod }

class AppConfig {
  static late Flavor flavor;

  static String get url => dotenv.env['URL'] ?? '';

  static void init(Flavor f) {
    flavor = f;
  }
}
