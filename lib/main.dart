import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_configuration.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = AppConfiguration.standard();
  runApp(ZfHelperApp(configuration: configuration));
}
