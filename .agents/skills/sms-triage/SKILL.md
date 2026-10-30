---
name: sms-triage
description: Triage, diagnose, scaffold, and verify community bank SMS format contributions submitted via GitHub issues.
---

# SMS Contribution Triage Guide

This skill guides the inspection, diagnostic breakdown, regex template development, RAG exemplar addition, and test verification for community-contributed bank SMS alerts.

---

## 1. Overview & Workflow

When users contribute bank SMS formats via the app, they create GitHub issues with titles starting with `[Format Contribution]:` containing sanitized SMS bodies and expected JSON extractions.

The triage workflow has 4 stages:

1. **Scan & Filter**: Read open GitHub issues using the local CLI tool (`tool/dev/triage_sms_issues.dart`).
2. **Diagnose**: Run deterministic checks using `SmsParser` and regex diagnostics:
   - Filter out invalid non-transaction alerts (e.g. pending mandates, standing instructions due, OTPs).
   - If already recognized, report the template ID.
   - If unrecognized, isolate the failure bottleneck (date formatting, ordinal suffixes, missing prepositions, or multi-line structures).
3. **Scaffold & Add**:
   - Update shared regex fragments or add a new `SmsTemplate` in `lib/src/core/parser.dart`.
   - Add a curated `RagExemplar` in `lib/src/core/rag_exemplars.dart`.
   - Add regression tests in `test/core_parser_test.dart`.
   - Verify zero regressions: `flutter test` and `dart analyze`.
4. **Reply & Close**:
   - Use `--reply` to post the acceptance or polite rejection comment directly to the GitHub issue with local user confirmation.
   - Link closed issues in the commit/PR: `Closes #<issue_number>`.

---

## 2. CLI Tool Usage

The tool runs locally and interacts with GitHub via the official `gh` CLI.

### Scan all open contribution issues
```bash
dart run tool/dev/triage_sms_issues.dart
```

### Scan a specific issue (open or closed)
```bash
dart run tool/dev/triage_sms_issues.dart --issue=95
```

### Scan all issues including previously closed ones
```bash
dart run tool/dev/triage_sms_issues.dart --all
```

### Triage with automated code scaffolding (RAG exemplar & unit test snippets)
```bash
dart run tool/dev/triage_sms_issues.dart --scaffold
```

### Triage and interactively reply to GitHub issues
```bash
dart run tool/dev/triage_sms_issues.dart --reply
```

---

## 3. Invariants & Rules

- **Direction Integrity**: Direction (`debit` vs `credit`) must come strictly from the matched template, never keyword searches.
- **Strict Month Pattern**: Dates with month names must follow `_monthPattern` (`Jan(?:uary)?|...|Dec(?:ember)?`).
- **Sanitized Values**: Masked accounts (`*XXXX` or `xxxxxx`) and references (`[MASKED]`) must parse gracefully without crashing or corrupting database indexes.
- **Test-by-Default**: Every newly accepted bank SMS format **must** have a dedicated regression test in `test/core_parser_test.dart`.
- **Local Approval Gate**: Never push or merge changes without explicit authorization from the developer. Commits stay on feature branches (`feat/...`).
