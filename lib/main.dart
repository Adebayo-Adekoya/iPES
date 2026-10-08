import 'package:flutter/material.dart';

import 'app/controller.dart';
import 'app/services.dart';
import 'app/shell.dart';
import 'core/library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = LibraryController(
    library: Library(storage: defaultStorage()),
    files: PlatformFileService(),
  );
  runApp(IpesApp(controller: controller));
  await controller.start();
}
