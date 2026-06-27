# Accessibility Validation Report

## Target

WCAG 2.1 AA aligned submitted application.

## Implemented

- Semantic `header`, `main`, `section`, headings, labels, and lists.
- Skip link.
- Keyboard operation for file picker, search, filters, export, import, clear, and settings.
- Visible focus indicators.
- High contrast mode.
- Text scaling up to 140%.
- Live region for indexing and result status.
- Responsive layout without overlapping text at mobile widths.

## Manual Validation

Use `tests/manual_test_plan.md`. Browser-based WAVE and platform screen-reader validation should be performed in the production environment.

## Known Limitations

Automated Google Accessibility Scanner and WAVE results cannot be generated from this terminal-only environment. The UI is prepared for those checks.
