import 'package:firebase_core/firebase_core.dart';
import '../firebase_options_prod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../app_config.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.prod');
  AppConfig.init(Flavor.prod);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Hello Flavor')),
      ),
    );
  }
}
