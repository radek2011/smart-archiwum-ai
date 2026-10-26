import 'dart:html' as html;

String? readSessionValue(String key) {
  try { return html.window.sessionStorage[key]; } catch (_) { return null; }
}
void writeSessionValue(String key, String value) {
  try { html.window.sessionStorage[key] = value; } catch (_) {}
}
void removeSessionValue(String key) {
  try { html.window.sessionStorage.remove(key); } catch (_) {}
}
