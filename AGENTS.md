# Repository guidelines

These instructions apply to the entire repository.

## Communication style

- Never use em dashes when communicating, writing code, or documenting.
- Do not use strong and expressive language that has no meaning.
- Be concise in your communications.

## Workspace

- `apps/*` contains Dart-only application cores. `frontends/*` contains Flutter
  applications. `packages/*` contain shared pacakges, split by responsibility
  and purpose.
- Shared packages must not depend on application cores or frontends.
  `apps/notes` consumes shared packages; `frontends/notes` consumes that core.
- Keep repository-wide, documentation in `docs`. Keep package- and app-specific
  documentation beside its owner.
- [Implementation details](/docs/IMPLEMENTATION_DETAILS.md) contains general
  information on data modeling and fundamental operational principlies of
  Claudare applications.

## Dependencies

- Pub owns the single root `pubspec.lock`. Never edit, copy, merge, or delete a
  lockfile manually, and do not commit member lockfiles.
- Change dependencies through the owning `pubspec.yaml` or Pub command.
- Resolve the workspace from its root with `fvm dart pub get`, not separate
  member-level resolves.
- Reference workspace members by compatible version constraints, never by path,
  Git dependency, or submodule.
- Do not add external dependencies unless requested or approved. Local workspace
  references are allowed.

## Editing files

- Use `apply_patch` for file edits instead of ad hoc Python, shell, or other
  scripts that rewrite files.
- Format Markdown with lines no wider than 80 characters.
- Do not apply unrelated changes or bug fixes unless asked. Leave unexpected
  issues unedited and report them to the user. During planning, you may ask
  whether those issues should be fixed.

## Code reviews

- When asked to review code, inspect only the given scope and do not edit files.
- Return three concise lists: bugs, improvements, and feedback. Number items
  within each list using the prefixes `B`, `I`, and `F`, and include locations
  for each finding.

## Code

- Follow [CONVENTIONS.md](CONVENTIONS.md) for new and modified code. Do not
  refactor unrelated existing deviations.
- Use the logger from `claudare_logging`. There is no global logger. Do not add
  ad hoc prints.
- Breaking changes are encouraged as the project is under development. Do not
  add compatibility paths. Do not add tests related to breaking changes.
- Keep shared analyzer policy at the repository root without member overrides.
- Use `///` to document key classes and interfaces. Use `[]` to reference code.
  Keep documentation short and to the point.

## Documentation

- Keep Markdown documentation concise.
- Frontend READMEs are public installiton/documentation/overview page for app
  users.
- Package READMEs explain when to use the package and how to begin using it.
  Prefer a short usage example over lists of classes and methods.
- Keep signatures, parameters, return values, and individual method behavior in
  Dart API comments. Do not repeat them in Markdown.
- Include only guidance that API comments cannot explain well, such as choosing
  between APIs, combining them, or important usage constraints.
- Omit details that are obvious from names or declarations. If the README adds
  no useful guidance beyond the code, keep it to a short description. Do not
  require public import statements.
- App README files provide a short description of the app, its user-facing
  features, and significant limitations.
- Do not add internal architecture, algorithms, lifecycle details, private
  types, implementation notes, or validation logs to Markdown documentation.
- During implementation, update documentation only when the public API or
  user-facing app information changes. Keep updates brief. When unsure, ask
  before editing documentation.
- Verify source before changing implementation status, and fix links when
  documents move.
- Keep normative coding conventions in `CONVENTIONS.md` rather than duplicating
  them elsewhere.

## Tests

- Name each test for one observable behavior and assert it when required.
  Separate success, failure, and distinct lifecycle scenarios.
- Use tables only for cases sharing setup, actions, and assertion structure;
  vary data only. Write separate tests for workflows needing conditional logic.
- Test rules in their owning layer; focus widget tests on rendering and wiring.
- Check existing coverage; skip duplicate, trivial, or obsolete tests.
- Share setup through small helpers when needed; keep actions and assertions
  explicit.

## Validation

For workspace changes affecting code, run:

```sh
fvm dart analyze
fvm dart run melos test
```

For a code change within one member, run root analysis and the relevant tests.
Use the full Melos command for cross-workspace code changes. Flutter tests use
`--no-pub`, so resolve dependencies before testing after dependency changes.

For documentation-only changes analysis and tests are unnecessary. Report only
checks actually run, categorized as static checks, tests, builds, or runtime
verification.
