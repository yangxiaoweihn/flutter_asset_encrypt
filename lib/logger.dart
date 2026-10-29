class Logger {
  factory Logger() => _instance;

  Logger._();

  static late final Logger _instance = Logger._();

  bool isDebug = false;

  String? tag = 'encrypt';

  void debug(Object msg) {
    if (isDebug) {
      print('${tag == null ? '' : '$tag: '}$msg');
    }
  }
}
