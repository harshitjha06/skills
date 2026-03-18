---
name: query-definition
description: Structured template for documenting code violations with detection rules and examples for CodeQL query generation. Use when developers need to (1) Document violation patterns for CodeQL analysis, (2) Define scope and file patterns for code scanning, (3) Specify detection conditions with violation and non-violation rules, (4) Provide negative examples (code that should be flagged) and positive examples (code that should NOT be flagged).
---

# Query Definition Template

This skill provides a structured template for documenting code violations that will be used to generate CodeQL queries.

## Template Structure

A query definition document must include the following sections:

### Scope

Define the file types to analyze using a glob pattern (e.g., `**/*.cs` for C#, `**/*.java` for Java).

### Detection Instructions

Describe each violation pattern with:
- **Pattern name**: A descriptive name for the violation type
- **"It is not a violation if..."**: Conditions where the pattern is acceptable
- **"It is a violation if..."**: Conditions that constitute a violation
- **How to Distinguish**: Guidance on edge cases

### Negative Examples

Code examples that **SHOULD be flagged** as violations. Include:
- Multiple violation types if applicable
- Edge cases that might be confused with violations
- Comments explaining why each example is a violation

### Positive Examples

Code examples that should **NOT be flagged** (correct implementations). Include:
- Comments explaining what makes the implementation correct
- Best practices demonstrated

## Reference

See [query-definition-template.md](references/query-definition-template.md) for the complete template with all sections and placeholders.
