class GetStatisticsResult {
  final int eventCount;
  final int storageSize; // bytes

  GetStatisticsResult({required this.eventCount, required this.storageSize});
}

// administrative functions for application management
abstract interface class EventStoreAdministration {
  Future<GetStatisticsResult> getStatistics();
  Future<void> reset();
}
