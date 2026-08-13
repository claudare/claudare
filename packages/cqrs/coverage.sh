#!/bin/sh
set -eu

fvm dart run coverage:test_with_coverage --branch-coverage
genhtml coverage/lcov.info \
  --branch-coverage \
  --ignore-errors inconsistent,inconsistent \
  --output-directory coverage/html \
  --title cqrs
