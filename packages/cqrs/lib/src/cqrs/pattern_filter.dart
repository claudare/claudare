enum PatternFilterType { exact, startsWith, any }

class PatternFilter {
  final PatternFilterType type;
  final String pattern;

  const PatternFilter({required this.type, required this.pattern});

  const PatternFilter.exact(this.pattern) : type = PatternFilterType.exact;
  const PatternFilter.startsWith(this.pattern)
    : type = PatternFilterType.startsWith;
  const PatternFilter.any() : type = PatternFilterType.any, pattern = '*';

  factory PatternFilter.fromString(String value) {
    final catchAllIndex = value.indexOf('*');
    if (catchAllIndex == -1) {
      return PatternFilter.exact(value);
    }

    if (catchAllIndex == 0) {
      assert(value.length == 1, "Wildcard pattern must be '*' only");

      return PatternFilter.any();
    }

    final prefix = value.substring(0, catchAllIndex);
    return PatternFilter.startsWith(prefix);
  }

  bool doesMatchPath(String path) {
    if (path == '*') {
      return true;
    }

    switch (type) {
      case PatternFilterType.any:
        return true;
      case PatternFilterType.startsWith:
        return path.startsWith(pattern);
      case PatternFilterType.exact:
        return path == pattern;
    }
  }

  @override
  String toString() {
    switch (type) {
      case PatternFilterType.any:
        return 'PatternFilter.any()';
      case PatternFilterType.startsWith:
        return 'PatternFilter.startsWith($pattern)';
      case PatternFilterType.exact:
        return 'PatternFilter.exact($pattern)';
    }
  }
}
