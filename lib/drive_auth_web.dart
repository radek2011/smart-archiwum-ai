import 'dart:js_interop';

@JS('smartDriveAuthorize')
external JSPromise<JSString> _authorizeDrive(JSString clientId);

Future<String> authorizeDrive(String clientId) async {
  final value = await _authorizeDrive(clientId.toJS).toDart;
  return value.toDart;
}
