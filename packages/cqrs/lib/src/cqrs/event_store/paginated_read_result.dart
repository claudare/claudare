class PaginatedResult<T> {
  final List<T> data;
  final int? next;

  const PaginatedResult({required this.data, required this.next});
}
