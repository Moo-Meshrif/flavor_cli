enum Flavor { dev, stage, prod }

class AppConfig {
  static late Flavor flavor;
  static late String url;

  static void init(Flavor f) {
    flavor = f;
    // TODO: Fill in your flavor values here
    switch (f) {
      case Flavor.dev:
        url = 'FILL_ME';
        break;
      case Flavor.stage:
        url = 'FILL_ME';
        break;
      case Flavor.prod:
        url = 'FILL_ME';
        break;
    }
  }
}
