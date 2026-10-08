import 'package:flutter/material.dart';

import 'app/controller.dart';
import 'app/services.dart';
import 'app/shell.dart';
import 'app/startup.dart';
import 'core/library.dart';

Future<void> main() async {
  Startup.clock.start(); // start timing as early as possible
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LibraryController(
    library: Library(storage: defaultStorage()),
    files: PlatformFileService(),
  );
  runApp(IpesApp(controller: controller));
  binding.waitUntilFirstFrameRasterized.then((_) {
    Startup.firstFrameMs = Startup.clock.elapsedMicroseconds / 1000;
  });
  await controller.start();
  Startup.libraryReadyMs = Startup.clock.elapsedMicroseconds / 1000;
}
