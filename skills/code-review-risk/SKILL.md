---
name: code-review-risk
description: Review changes for bugs, regressions, missing tests, safety gaps, public/private leaks, and architecture drift before stylistic comments.
keywords: [review, bugs, regressions, tests, safety, architecture]
---

# code-review-risk

Review for risk first.

## Procedure

1. Read the diff and the relevant tests/docs for the behavior being changed.
2. Prioritize correctness, regressions, missing validation, public/private leaks, and architecture boundary violations.
3. Check whether changes conflict with Constitution, ADRs, decision map, naming, storage, surface registry, or host ownership.
4. Ground each finding in a concrete file/line and describe the user-visible or operational impact.
5. Separate findings from open questions and low-risk polish.
6. If no issues are found, state the remaining test gaps or residual risk.

## Constraints

- Do not lead with style nits when behavioral risk exists.
- Do not assume generated or staged files are safe without inspection.
- Do not recommend reverting unrelated user work.
