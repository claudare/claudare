enum LogFilterType { exact, startsWith, all }

class LogFilter {
  final LogFilterType type;
  final String pattern;

  const LogFilter({required this.type, required this.pattern});

  const LogFilter.exact(this.pattern) : type = LogFilterType.exact;
  const LogFilter.startsWith(this.pattern) : type = LogFilterType.startsWith;
  const LogFilter.all() : type = LogFilterType.all, pattern = '';

  bool doesMatchPath(String path) {
    switch (type) {
      case LogFilterType.all:
        return true;
      case LogFilterType.startsWith:
        return path.startsWith(pattern);
      case LogFilterType.exact:
        return path == pattern;
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
