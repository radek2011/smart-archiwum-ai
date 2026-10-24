import 'drive_auth_stub.dart'
  if (dart.library.js_interop) 'drive_auth_web.dart' as platform;

/// Returns a temporary Google access token. Never persist it.
Future<String> authorizeDrive(String clientId) =>
    platform.authorizeDrive(clientId);
