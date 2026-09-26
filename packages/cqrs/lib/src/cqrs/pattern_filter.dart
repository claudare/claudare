enum PatternFilterType { exact, startsWith, all }

class PatternFilter {
  final PatternFilterType type;
  final String pattern;

  const PatternFilter({required this.type, required this.pattern});

  const PatternFilter.exact(this.pattern) : type = PatternFilterType.exact;
  const PatternFilter.startsWith(this.pattern)
    : type = PatternFilterType.startsWith;
  const PatternFilter.all() : type = PatternFilterType.all, pattern = '*';

  factory PatternFilter.fromString(String value) {
    final catchAllIndex = value.indexOf('*');
    if (catchAllIndex == -1) {
      return PatternFilter.exact(value);
    }

    if (catchAllIndex == 0) {
      assert(value.length == 1, "Wildcard pattern must be '*' only");

      return PatternFilter.all();
    }

    final prefix = value.substring(0, catchAllIndex);
    return PatternFilter.startsWith(prefix);
  }

  bool doesMatchPath(String path) {
    if (path == '*') {
      return true;
    }

    switch (type) {
      case PatternFilterType.all:
        return true;
      case PatternFilterType.startsWith:
        return path.startsWith(pattern);
      case PatternFilterType.exact:
        return path == pattern;
    }
  }

  String path() {
    switch (type) {
      case PatternFilterType.all:
        return '*';
      case PatternFilterType.startsWith:
        return '$pattern/*';
      case PatternFilterType.exact:
        return pattern;
    }
  }

  @override
  String toString() {
    switch (type) {
      case PatternFilterType.all:
        return 'PatternFilter.any()';
      case PatternFilterType.startsWith:
        return 'PatternFilter.startsWith($pattern)';
      case PatternFilterType.exact:
        return 'PatternFilter.exact($pattern)';
    }
  }
}
