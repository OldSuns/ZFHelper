import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_configuration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = AppConfiguration.standard();
  await configuration.appearance.initialize();
  runApp(ZfHelperApp(configuration: configuration));
}
