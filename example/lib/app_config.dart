// GENERATED CODE - DO NOT MODIFY BY HAND

enum Flavor { dev, stage, prod }

class AppConfig {
  static late Flavor flavor;
  static late String url;

  static void init(Flavor f) {
    flavor = f;
    switch (f) {
      case Flavor.dev:
        url = '';
        break;
      case Flavor.stage:
        url = '';
        break;
      case Flavor.prod:
        url = '';
        break;
    }
  }
}
