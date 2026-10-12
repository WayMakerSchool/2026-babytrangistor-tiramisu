import 'platform_log_io.dart' if (dart.library.html) 'platform_log_web.dart';

void platformLog(String message) => writePlatformLog(message);
