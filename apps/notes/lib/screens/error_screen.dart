import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';

void navigateToErrorScreen(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder:
          (context) =>
              ErrorScreen(errors: [(error: error, stackTrace: stackTrace)]),
    ),
    (route) => false,
  );
}

class ErrorScreen extends StatelessWidget {
  final List<CqrsProjectionError> errors;

  ErrorScreen({super.key, required List<CqrsProjectionError> errors})
    : errors = List.unmodifiable(errors);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 56,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: errors.length,
                    separatorBuilder:
                        (context, index) => const SizedBox(height: 12),
                    itemBuilder:
                        (context, index) => ProjectionErrorDetails(
                          index: index,
                          details: errors[index],
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProjectionErrorDetails extends StatelessWidget {
  final int index;
  final CqrsProjectionError details;

  const ProjectionErrorDetails({
    super.key,
    required this.index,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              'Error ${index + 1}: ${details.error}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SelectableText(
              'Stack trace:\n${details.stackTrace}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
