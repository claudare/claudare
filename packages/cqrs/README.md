# cqrs

CQRS infrastructure for the Claudare workspace.

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
