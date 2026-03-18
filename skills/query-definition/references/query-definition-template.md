# Query Definition: [Descriptive Name of the Query]

## Scope

```glob
**/*.[extension]
```

Specify the file types to analyze (e.g., `**/*.cs` for C#, `**/*.java` for Java, `**/*.py` for Python).

## Detection Instructions

Provide detailed instructions for detecting violations. Be specific about what constitutes a violation and what does not.

### Pattern A: [Name of First Violation Pattern]

Describe the first type of violation to detect.

**It is not a violation** if [condition where this pattern is acceptable].

**It is not a violation** if [another acceptable condition].

**It is a violation** if [condition that constitutes a violation].

**It is a violation** if [another violation condition].

### Pattern B: [Name of Second Violation Pattern] (if applicable)

Describe the second type of violation to detect.

**It is not a violation** if [condition where this pattern is acceptable].

**It is a violation** if [condition that constitutes a violation].

### How to Distinguish [Edge Case Category]

Provide guidance on distinguishing edge cases:

1. **[Clue 1]**: How to identify one type of usage
2. **[Clue 2]**: How to identify another type of usage
3. **[Clue 3]**: Additional distinguishing factors

## Negative Example

Provide code examples that **SHOULD be flagged** as violations.

### Violation Type A: [Description]

```[language]
// Example code that demonstrates the violation
// Include comments explaining why this is a violation
```

### Violation Type B: [Description] (if applicable)

```[language]
// Another example of violating code
```

### NOT a Violation: [Edge Case That Might Be Confused]

```[language]
// Example that might look like a violation but is NOT
// Explain why this is acceptable
```

**Why these are problematic:**

**Type A ([Pattern Name]):**
1. Explanation of why pattern A is problematic
2. Additional context

**Type B ([Pattern Name]):**
1. Explanation of why pattern B is problematic
2. Additional context

## Positive Example

Provide code examples that should **NOT be flagged** (correct implementations).

```[language]
// Example of correct code that follows best practices
// Include comments explaining why this is correct
```

**Why this is correct:**
1. Explanation of what makes this implementation correct
2. Additional best practices demonstrated
3. Any relevant patterns or techniques used
