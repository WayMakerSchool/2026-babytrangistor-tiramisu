import 'dart:js_interop';

@JS('console.log')
external void _consoleLog(JSAny? value);

void writePlatformLog(String message) {
  _consoleLog(message.toJS);
}
