---
name: rg
description: >-
  Fast recursive text search with ripgrep. Use when searching files for patterns,
  finding code references, filtering by file type or path, replacing text across
  files, or any grep-like operation. Faster and smarter than grep with sensible
  defaults (respects .gitignore, skips binary files, recursive by default).
---

# ripgrep

## Quick start

```bash
# Search current directory recursively
rg "TODO"
# Search specific file types
rg "import" --type py
# Search with context lines
rg "error" -C 3
# Case-insensitive
rg -i "config"
# Fixed string (not regex)
rg -F "func()" 
```

## Search patterns

### Basic

```bash
rg "pattern"                    # regex search, recursive from cwd
rg "pattern" src/               # search specific directory
rg "pattern" file.txt           # search specific file
rg -F "exact.match()"          # fixed string, no regex
rg -i "case insensitive"       # ignore case
rg -S "smartCase"              # smart case: case-sensitive only if pattern has uppercase
rg -w "word"                   # whole word match
rg -x "entire line"            # match must span entire line
```

### Regex

```bash
rg "fn\s+\w+\("                # Rust function definitions
rg "import\s+{.*}"             # JS named imports
rg "TODO|FIXME|HACK"           # multiple patterns
rg "v\d+\.\d+\.\d+"           # semantic versions
rg -P "(?<=@)\w+"              # PCRE2 lookaround (needs -P)
rg -e "first" -e "second"      # multiple patterns (OR)
```

## Filtering

### By file type

```bash
rg "pattern" -t py             # only Python files
rg "pattern" -t js -t ts       # JavaScript and TypeScript
rg "pattern" -T test           # exclude test files
rg --type-list                 # show all known file types
rg --type-add 'config:*.{yml,yaml,toml}' -t config "key"  # custom type
```

### By path

```bash
rg "pattern" -g "*.rs"         # only .rs files (glob)
rg "pattern" -g "!test/**"     # exclude test directory
rg "pattern" -g "src/**"       # only src directory
rg "pattern" --hidden          # include hidden files (dotfiles)
rg "pattern" --no-ignore       # don't respect .gitignore
rg "pattern" -l                # list only filenames with matches
rg "pattern" -c                # count matches per file
```

## Output control

```bash
rg "pattern" -n                # line numbers (default)
rg "pattern" -N                # no line numbers
rg "pattern" -C 3              # 3 lines context (before + after)
rg "pattern" -B 2              # 2 lines before
rg "pattern" -A 2              # 2 lines after
rg "pattern" --json            # JSON output (for parsing)
rg "pattern" -o                # only matching text, not full line
rg "pattern" --stats           # show match statistics
rg "pattern" --count-matches   # total match count per file
```

## Replace

```bash
# Preview replacements (stdout only, doesn't modify files)
rg "old" --replace "new"
rg "v(\d+)" --replace "version $1"

# Actually modify files (pipe through other tools)
rg "old" -l | xargs sed -i 's/old/new/g'
```

## Example: Find function definitions

```bash
# Python
rg "def \w+\(" -t py -l
# JavaScript/TypeScript
rg "(function|const|let|var)\s+\w+\s*=" -t js -t ts
# Go
rg "func \w+\(" -t go
# Rust
rg "fn \w+\(" -t rust
```

## Example: Search and replace across codebase

```bash
# Find all occurrences first
rg "OldClassName" -t py --stats
# Preview replacement
rg "OldClassName" -t py --replace "NewClassName"
# Apply (using sed)
rg "OldClassName" -t py -l | xargs sed -i 's/OldClassName/NewClassName/g'
# Verify
rg "OldClassName" -t py  # should return nothing
```

## Example: Explore unfamiliar codebase

```bash
# Find entry points
rg "def main|fn main|func main|static void main" -l
# Find config files
rg --files -g "*.{yml,yaml,toml,json,ini}" | head -20
# Find TODOs and FIXMEs
rg "TODO|FIXME|HACK|XXX" --stats
# Find imports of a module
rg "import.*requests" -t py
# List all file types in repo
rg --files --stats 2>&1 | tail -5
```

## Gotchas

- **No in-place editing.** `--replace` only prints to stdout. Use `rg -l | xargs sed -i` for file modification.
- **PCRE2 needed for lookaround.** `-P` flag enables PCRE2 regex. Without it, lookahead/lookbehind won't work.
- **Smart case is not default.** Use `-S` or `--smart-case` explicitly. Default is case-sensitive.
- **Binary files skipped.** rg skips binary files by default. Use `--binary` or `-a` to search them.
- **Symlinks not followed.** Use `-L` / `--follow` to follow symbolic links.
- **`.gitignore` respected.** rg reads `.gitignore` and skips matched files. Use `--no-ignore` to search everything.
