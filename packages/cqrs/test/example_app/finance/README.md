# Finance application

A small CQRS example with account commands and projection queries.

```dart
await app.command.openAccount(accountId: 'checking', name: 'Checking');
await app.command.atmDeposit(accountId: 'checking', amount: 100);
final summary = await app.query.accountSummary('checking');
assert(summary.balance == 100);
```

Queries return independent models. Query again after commands to read changes.
