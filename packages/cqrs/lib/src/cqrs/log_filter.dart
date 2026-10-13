enum LogFilterType { exact, startsWith, all }

class LogFilter {
  final LogFilterType type;
  final String pattern;

  const LogFilter({required this.type, required this.pattern});

  const LogFilter.exact(this.pattern) : type = LogFilterType.exact;
  const LogFilter.startsWith(this.pattern) : type = LogFilterType.startsWith;
  const LogFilter.all() : type = LogFilterType.all, pattern = '*';

  factory LogFilter.fromString(String value) {
    final catchAllIndex = value.indexOf('*');
    if (catchAllIndex == -1) {
      return LogFilter.exact(value);
    }

    if (catchAllIndex == 0) {
      assert(value.length == 1, "Wildcard pattern must be '*' only");

      return LogFilter.all();
    }

    final prefix = value.substring(0, catchAllIndex);
    return LogFilter.startsWith(prefix);
  }

  bool doesMatchPath(String path) {
    if (path == '*') {
      return true;
    }

    switch (type) {
      case LogFilterType.all:
        return true;
      case LogFilterType.startsWith:
        return path.startsWith(pattern);
      case LogFilterType.exact:
        return path == pattern;
    }
  }

  String path() {
    switch (type) {
      case LogFilterType.all:
        return '*';
      case LogFilterType.startsWith:
        return '$pattern/*';
      case LogFilterType.exact:
        return pattern;
    }
  }

  @override
  String toString() {
    switch (type) {
      case LogFilterType.all:
        return 'LogFilter.all()';
      case LogFilterType.startsWith:
        return 'LogFilter.startsWith($pattern)';
      case LogFilterType.exact:
        return 'LogFilter.exact($pattern)';
    }
  }
}
