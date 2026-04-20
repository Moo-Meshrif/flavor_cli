import 'package:firebase_core/firebase_core.dart';
import '../firebase_options_prod.dart';
import '../app_config.dart';
import 'package:flutter/material.dart';

void main() async {
  AppConfig.init(Flavor.prod);
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform,);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Hello Flavor: prod')),
      ),
    );
  }
}
