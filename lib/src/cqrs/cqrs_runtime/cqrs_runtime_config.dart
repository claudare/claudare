class CqrsRuntimeConfig {
  /// size for the pagination of event store queries
  final int eventStorePageSize;

  const CqrsRuntimeConfig({required this.eventStorePageSize});

  CqrsRuntimeConfig.defaults() : this(eventStorePageSize: 20);
}
