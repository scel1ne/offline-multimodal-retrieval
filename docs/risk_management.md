# Risk Management Plan

Author: Celine Song
Plan version: 1.0
Review cadence: weekly (every Monday), with an out-of-cycle review on any
production-affecting incident.

## Risk Register

| ID | Risk | Impact | Probability | Trigger | Mitigation | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| R-01 | Large ML models are slow on consumer CPUs | High | Medium | End-to-end indexing of > 100 files exceeds 30 s on the reference Mac | Quantize TFLite models, batch embedding calls, cache vectors to disk, surface a progress indicator | Celine Song |
| R-02 | PDF / DOCX parsing edge cases (corrupt, encrypted, scanned) | Medium | High | `LocalContentParser` returns empty text or throws on any of the 5 corpus samples | Use PDFium + Apache Tika in production, keep parser unit tests at 100% branch coverage, fall back to filename + size for un-parseable files | Celine Song |
| R-03 | Accessibility regressions slip into a release | High | Medium | Any change to `lib/src/ui/home_screen.dart` (or new screen) not accompanied by a passing `accessibility_test.dart` | Manual keyboard-only check before each release, run WAVE / aXe on the running macOS app, VoiceOver smoke test, gate merges on green accessibility tests | Celine Song |
| R-04 | Private data leaves the device | High | Low | Any new dependency that opens a network socket, or any `dart:io HttpClient` call in `lib/` | No network by default, security review for any new outbound call, `security_review.md` checklist run on every release, opt-in only for any future cloud feature | Celine Song |
| R-05 | License restrictions for models or datasets | High | Medium | Adding any new `.tflite`, `.pt`, `.mlpackage`, or dataset under `assets/` or `fixtures/` | Verify license (Apache 2.0 / MIT / Apple ML Model Research License) before redistribution, record license + source URL in `oss_compliance.md` | Celine Song |
| R-06 | Local index size grows unbounded | Medium | Medium | Library > 10 000 records, or `dist/` build size > 500 MB | Use Chroma / local SQLite in production for large libraries, add per-file size limits, document cleanup in `maintenance_guide.md` | Celine Song |
| R-07 | MobileCLIP TFLite conversion breaks the production path | Medium | Medium | `assets/models/mobileclip_image_encoder.tflite` missing or fails to load at app start | Keep CoreML `mobileclip_s0_image.mlpackage` as a working fallback, run the ONNX-to-TFLite script on every model refresh, smoke-test indexing at least 1 image after each conversion | Celine Song |
| R-08 | macOS native channel is not portable to other OSes | Low | High | Stakeholder asks for Windows or Linux build | Document the macOS-only constraint in `user_manual.md` and `PRD.md`; port the `local_parsers` MethodChannel to Windows / Linux if the requirement is added | Celine Song |
| R-09 | Local Flutter / Tika / Chroma tooling drifts out of date | Low | Medium | `flutter --version` or `chroma --version` no longer matches the pinned values in this document | Pin versions in `pubspec.yaml` and `scripts/bootstrap_strict_env.sh`, re-run the validation checklist quarterly | Celine Song |
| R-10 | Test coverage drops below 90% gate | Medium | Low | A new module is added without corresponding tests | Coverage gate in `testing_report.md`; CI / pre-release step fails the build if line coverage < 90% | Celine Song |

## Risk Heat Map

```
                 Probability →
                 Low        Medium     High
Impact ↓
High             R-04       R-01 R-03  R-05
Medium                       R-02 R-06
                            R-07 R-09
Low                                    R-08
                                        R-10
```

## Review Cadence

- **Weekly review (Mondays):** open each row, update Probability / Impact,
  log any triggered Mitigations in the change log below, and re-rank.
- **Out-of-cycle review:** any incident that triggers R-01, R-03, R-04, or
  R-05 must be reviewed within 24 hours.
- **Quarterly deep review:** validate that all 10 risks still apply and
  that the Mitigations are still in place.

## Escalation Path

1. Engineer (Celine Song) triages the trigger and updates the row.
2. If the Mitigation does not resolve the issue within one iteration, the
   risk is escalated to a full Plan review and a follow-up is recorded in
   the change log.

## Change Log

| Date | Author | Change |
| --- | --- | --- |
| 2026-06-27 | Celine Song | Initial risk register drafted and signed-off for Week 1 delivery |

## Sign-off

| Role | Name | Signature | Date |
| --- | --- | --- | --- |
| Risk Owner | Celine Song | _signed_ | 2026-06-27 |
