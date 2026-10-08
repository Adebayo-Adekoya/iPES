/// Start-up timing, recorded once by main() for the Device check screen.
library;

class Startup {
  Startup._();

  /// Started at the top of main().
  static final Stopwatch clock = Stopwatch()..start();

  /// main() → first frame drawn.
  static double? firstFrameMs;

  /// main() → library loaded and shown (includes building the sample
  /// library on the very first launch).
  static double? libraryReadyMs;

  /// True when this launch created the sample library.
  static bool firstLaunch = false;
}
