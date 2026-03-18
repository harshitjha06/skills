---
name: skill-from-cli
description: >-
  Convert any CLI tool into a high-quality Agent Skill by crawling its help tree,
  researching real-world usage patterns, and generating a curated SKILL.md with
  references. Use when asked to create a skill for a CLI tool, turn a command-line
  tool into an agent skill, generate agent instructions from a CLI, or wrap any
  existing CLI for agent consumption. Works with any framework: Cobra, Click,
  Argparse, Clap, oclif, Commander, or custom. Always use this skill when the
  input is an existing CLI binary — even if the user just says "create a skill
  for <tool>".
---

# CLI to Agent Skill

Convert any command-line tool into an agent skill that follows the
[Agent Skills open standard](https://agentskills.io/specification).

The goal: produce a skill an agent can load and immediately use the CLI
effectively — as if it had months of experience with the tool.

## What makes a great CLI skill

Study the [playwright-cli skill](https://github.com/microsoft/playwright-cli/tree/main/skills/playwright-cli)
before generating. It's the gold standard. Notice:

- **Example-driven.** Commands shown in context, not cataloged.
- **Task-oriented.** Organized by what you want to accomplish, not by the command tree.
- **Progressive disclosure.** Core patterns in SKILL.md, deep topics in `references/`.
- **High agent freedom.** Techniques and patterns, not rigid step-by-step procedures.
- **Concise.** Every line earns its place. No padding, no hedging.

A great CLI skill is a cheat sheet an expert would pin to their wall — not a man page.

See [references/output-examples.md](references/output-examples.md) for complete
examples of generated skills for gh, ripgrep, and ffmpeg — three different CLI
archetypes (subcommand-heavy, flag-heavy, and massive/custom).

## Before you start

```bash
# Verify the CLI exists and get version
which <cli> && <cli> --version
# Get root help — this tells you the framework and scope
<cli> --help 2>&1 | head -80
```

Detect the framework from help output patterns. Read
[references/cli-frameworks.md](references/cli-frameworks.md) for detection
signatures and parsing rules for Cobra, Click, Argparse, Clap, oclif,
Commander, and custom CLIs.

If the CLI isn't installed, install it or ask the user for access.

## Crawl the help tree

Walk `--help` recursively to map every command, flag, and argument.

```bash
# Strip ANSI, merge stderr, disable pagers
PAGER=cat NO_COLOR=1 <cli> --help 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
# Recurse into subcommands
PAGER=cat NO_COLOR=1 <cli> <subcommand> --help 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
```

**Crawl rules:**
- Depth limit: 6 levels. Most CLIs are 2–3 deep.
- Timeout: 5s per invocation. Skip on hang.
- Track visited paths (some CLIs alias commands).
- Skip `completion`, `help`, and shell-completion subcommands.
- If `--help` is sparse, try `man <cli>`, `<cli> help <sub>`, or `<cli> --help all`.
- Dump raw crawl data to `/tmp/skill-crawl-<cli>.md` as working notes.

## Research real-world usage

This is what separates a generated reference from a real skill. Search for:

1. Official documentation and README
2. Common workflows and tutorials
3. Gotchas, pitfalls, and common mistakes
4. Cheat sheets and quick references

From research, identify:
- **The 20% of commands that cover 80% of real usage** — these go in SKILL.md
- **Multi-step workflows** people actually perform (not just individual commands)
- **Gotchas** that `--help` never tells you (flag order, destructive defaults, silent failures)
- **Deprecated or dangerous commands** — flag them explicitly

## Generate the skill

### Decide the structure

| CLI size | Structure |
|----------|-----------|
| ≤20 meaningful commands | Single SKILL.md |
| 20–60 commands | SKILL.md + task-specific `references/` |
| 60+ commands | SKILL.md as navigation hub + `references/` + optional `full-reference.md` for grep |

### Write the SKILL.md

**Frontmatter:**

```yaml
---
name: <cli-name>           # lowercase-hyphenated, matches directory, ≤64 chars
description: >-
  <What it does> and <key capabilities>. Use when <trigger conditions>.
  <Specific keywords for agent matching>.
---
```

Make the description slightly "pushy" — agents undertrigger skills. Include
adjacent use cases and alternate phrasings so the skill activates when needed.

**Body pattern** (adapt to the CLI, don't follow rigidly):

```markdown
# <CLI Name>

## Quick start
<3-5 commands that accomplish something real. Copy-paste-ready.>

## Commands
### <Task category 1>
<Commands shown in realistic context with inline # comments>

### <Task category 2>
<Commands shown in realistic context>

## <Setup / Auth — if needed>

## Example: <Real workflow name>
<Multi-step sequence>

## Example: <Another workflow>
<Multi-step sequence>

## Gotchas
- **<Pitfall>**: <what happens> → <what to do instead>

## Specific tasks
* **<Deep topic>** [references/<topic>.md](references/<topic>.md)
```

### Writing principles

**Show, don't explain.** Bash blocks with `#` comments over prose paragraphs.

**Task-oriented, not tree-oriented.** Group by what agents want to accomplish
("Deploy a container", "Review a PR"), not by the command hierarchy.

**Curate flags.** Show important flags in context where they're used. Never dump
a flag catalog — that's what `--help` is for.

**Quick start is mandatory.** First section after the title. The most common
workflow in 3–5 commands. An agent (or human) should be able to copy-paste this
and get a useful result.

**Real examples over abstract patterns.** Use concrete filenames, realistic
values, plausible scenarios. `docker run -d -p 8080:80 --name web nginx` beats
`docker run [OPTIONS] IMAGE [COMMAND]`.

**Under 500 lines.** Everything beyond that goes into `references/`. The agent
loads the full SKILL.md into context on activation — respect the token budget.

**Every line earns its place.** If removing a line doesn't reduce the agent's
effectiveness, remove it.

### Reference files

Each file in `references/`:
- Named after a **task** (`request-mocking.md`, not `networking.md`)
- Self-contained: follow the file to complete the task
- Concrete examples for every concept
- TOC if over 100 lines
- ~300 lines max each

Reference from SKILL.md with clear pointers:

```markdown
## Specific tasks
* **Request mocking** [references/request-mocking.md](references/request-mocking.md)
* **Test generation** [references/test-generation.md](references/test-generation.md)
```

### Output location

Ask the user where to write. Common paths:

| Platform | Path |
|----------|------|
| Claude Code | `.claude/skills/<cli>/` |
| OpenClaw | `<workspace>/skills/<cli>/` |
| GitHub Copilot | `.github/skills/<cli>/` |
| Generic | `skills/<cli>/` |

## Validate

Before delivering, verify:

- [ ] `name` is lowercase-hyphenated, matches directory, ≤64 chars
- [ ] `description` includes trigger conditions and keywords, ≤1024 chars
- [ ] SKILL.md body under 500 lines
- [ ] Quick start section exists and works (test it if possible)
- [ ] Organized by task, not by command tree
- [ ] Real examples with concrete values (no abstract placeholders)
- [ ] Gotchas section with non-obvious pitfalls
- [ ] Reference files use relative paths, each focused on one task
- [ ] No filler: every section would be missed if removed
- [ ] Reads naturally to an agent — not a man page, not a tutorial

Run the generated commands when possible to verify correctness.

## Edge cases

**No subcommands** (jq, rg, curl, ffmpeg): Organize by use case, not by flags.
These CLIs are often the hardest — the skill's value is showing which flag
combinations accomplish which tasks.

**REPL/TUI tools** (python, psql, redis-cli): Document both CLI flags and
interactive commands. Note the non-interactive mode agents should prefer.

**Auth-gated CLIs** (aws, gcloud, az): Include setup/auth section. Note
required env vars. Never include credentials.

**Plugin ecosystems** (kubectl+krew, docker+buildx): Cover the base CLI only.
Mention plugin existence, don't crawl them.

**Man-page-only tools** (git subcommands, traditional Unix): Parse SYNOPSIS
and DESCRIPTION from man output.

**Massive CLIs** (aws with 300+ services): Don't try to cover everything.
Focus on the most-used service commands. Use references for service-specific
deep dives. The skill's value is curation, not completeness.
