import 'dart:js_interop';

@JS('smartDriveOpenFile')
external void _openDriveFile(JSString id);

void openDriveFile(String id) => _openDriveFile(id.toJS);
