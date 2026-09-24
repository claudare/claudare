# cqrs

CQRS implementation for the Claudare workspace.

## Positions

Command, local event, and stream reads are inclusive of the requested position.
`null` means an empty command or event history when returned as its last local
sequence, or an absent stream when used as its version.

## Validation

Run the package tests from this directory with:

```sh
fvm dart test
```

Exercise order independence with:

```sh
fvm dart test --test-randomize-ordering-seed=random
```

Collect branch coverage with:

```sh
./coverage.sh
```

The script writes LCOV data to `coverage/lcov.info` and a human-readable report
to `coverage/html/index.html`.
