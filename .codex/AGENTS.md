# Codex Project Rules

- Do not run `git commit` or `git push` unless the user explicitly asks for that exact action.
- Do not create commits implicitly as part of implementation, verification, cleanup, or finalization.
- When summarizing work, report changed files and verification results without committing or pushing.
- Before any user-requested `git commit` or `git push`, inspect `assistants.json` and confirm its top-level `fastMode` field is `false`. If `fastMode` is `true`, do not commit or push; tell the user that `fastMode` is still enabled.
