# Contributing

Thank you for your interest in contributing to Atlas Network.

## Development Workflow

1. Create a feature branch from `main`.
2. Make focused, well-documented changes.
3. Run formatting and validation before committing.
4. Open a Pull Request with a clear description.

## Commit Messages

Follow a clear, descriptive style.

Examples:

```text
feat(terraform): add transit gateway module
docs: add ADR-0003
fix(ci): correct workflow permissions
```

## Code Standards

- Write clear documentation.
- Keep modules reusable.
- Prefer small, focused commits.
- Avoid committing secrets or Terraform state files.
- No `apply` in CI — plan-only, matching `atlas-foundation`'s gate.