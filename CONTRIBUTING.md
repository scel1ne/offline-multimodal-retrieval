# Contributing

## Local Development

This submission build has no package manager dependency. Open `app/index.html` directly and use `tests/run_tests.html` for browser-based tests.

## Standards

- Keep all processing local by default.
- Preserve keyboard and screen-reader accessibility for every new workflow.
- Add tests for parser, indexing, search ranking, and persistence changes.
- Keep UI copy plain and action-oriented.

## Pull Request Checklist

- Tests pass in `tests/run_tests.html`
- Manual accessibility checklist updated when UI changes
- Documentation updated for public APIs or behavior changes
- No cloud calls or telemetry added without explicit documentation and opt-in controls
