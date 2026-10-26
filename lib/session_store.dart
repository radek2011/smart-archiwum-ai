import 'session_store_stub.dart'
    if (dart.library.html) 'session_store_web.dart' as platform;

String? readSessionValue(String key) => platform.readSessionValue(key);
void writeSessionValue(String key, String value) => platform.writeSessionValue(key, value);
void removeSessionValue(String key) => platform.removeSessionValue(key);
