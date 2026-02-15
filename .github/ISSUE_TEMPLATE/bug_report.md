---
name: Bug Report
about: Report a bug to help us improve
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

A clear and concise description of what the bug is.

## To Reproduce

Steps to reproduce the behavior:

1. Go to '...'
2. Click on '...'
3. Enter '...'
4. See error

## Expected Behavior

A clear and concise description of what you expected to happen.

## Actual Behavior

What actually happened instead.

## Screenshots

If applicable, add screenshots to help explain your problem.

## Environment

Please complete the following information:

- **OS**: [e.g., Windows 10, macOS 13.0, Ubuntu 22.04]
- **R Version**: [e.g., 4.3.2]
- **Package Version**: [e.g., 0.1.0]
- **Browser** (if relevant): [e.g., Chrome 120, Firefox 121]

```r
# Run this and paste the output
sessionInfo()
```

## Reproducible Example

Please provide a minimal reproducible example (reprex):

```r
library(editable.submissionsync)

# Your code that reproduces the issue
store <- DataStore$new("test.duckdb", "test_table")
# ... rest of code
```

## Error Messages

```
Paste any error messages or stack traces here
```

## Additional Context

Add any other context about the problem here.

## Possible Solution

If you have suggestions on how to fix the bug, please describe them here.

## Checklist

- [ ] I have searched existing issues to ensure this is not a duplicate
- [ ] I have provided a minimal reproducible example
- [ ] I have included my session info
- [ ] I have included relevant error messages
