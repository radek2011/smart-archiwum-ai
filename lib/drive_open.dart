import 'drive_open_stub.dart'
  if (dart.library.js_interop) 'drive_open_web.dart' as platform;

void openDriveFile(String id) => platform.openDriveFile(id);
