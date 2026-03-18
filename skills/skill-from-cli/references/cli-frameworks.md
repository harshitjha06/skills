# CLI Framework Detection & Parsing

Identify the framework from `--help` output, then use matching extraction rules.

## Detection table

| Framework | Signature | Examples |
|-----------|-----------|----------|
| **Cobra** (Go) | `Available Commands:` + `Use "<cli> [command] --help"` | docker, kubectl, gh, hugo, terraform |
| **Click** (Python) | `Usage: <cli> [OPTIONS] COMMAND` + `Commands:` block | pip, flask, black, uvicorn |
| **Typer** (Python) | Click output + `╭─ Commands ─╮` rich panels | fastapi, typer-based tools |
| **Argparse** (Python) | `usage:` (lowercase) + `positional arguments:` / `options:` | stdlib Python tools |
| **Clap** (Rust) | `USAGE:` (caps) + `OPTIONS:` + `SUBCOMMANDS:` or `Commands:` (v4) | rg, fd, bat, cargo |
| **Kingpin** (Go) | `usage:` + `Flags:` + `commands:` (all lowercase) | prometheus, alertmanager |
| **Commander** (Node) | `Usage: <cli> [options] [command]` + `Commands:` | npm CLIs, create-react-app |
| **oclif** (Node) | `USAGE` + `COMMANDS` (caps, no colon) + `$ <cli> help [COMMAND]` | heroku, salesforce CLI |
| **urfave/cli** (Go) | `USAGE:` + `COMMANDS:` + `GLOBAL OPTIONS:` | nerdctl, act |
| **picocli** (Java) | `Usage: <cli>` + `Commands:` + `@|bold` markup in some | micronaut, quarkus CLI |
| **Custom/getopt** | No standard structure | git, curl, jq, ffmpeg |
| **Man page** | `NAME\n  <cli> -` + `SYNOPSIS` + `DESCRIPTION` | traditional Unix tools |

If unsure: default to "custom" — parse heuristically by matching flag lines
(`^\s+-`) and subcommand lines (indented `<word>  <description>` pairs).

---

## Cobra (Go)

The most consistent. Easiest to parse.

```
<Description>

Usage:
  <cli> [flags]
  <cli> [command]

Available Commands:
  <cmd>       <description>

Flags:
  -s, --long <type>   <description>

Global Flags:
      --config string   config file

Use "<cli> [command] --help" for more information.
```

**Extraction:**
- Subcommands: lines under `Available Commands:` — `^\s{2,}(\S+)\s{2,}(.+)$`
- May have sections: `Management Commands:`, `Core Commands:`
- Flags: under `Flags:` / `Global Flags:` — `^\s+(-\w,\s+)?--(\S+)\s+(\S+)?\s{2,}(.+)$`
- Plugin marker: `*` suffix (`buildx*  Docker Buildx`)
- Leaf detection: no `Available Commands:` in subcommand help = leaf
- Recurse: `<cli> <sub> --help`

---

## Click (Python)

```
Usage: <cli> [OPTIONS] COMMAND [ARGS]...

  <Description>

Options:
  --version      Show the version and exit.
  --help         Show this message and exit.

Commands:
  <cmd>  <description>
```

**Extraction:**
- Subcommands: under `Commands:` — `^\s{2}(\S+)\s{2,}(.+)$`
- Click truncates descriptions with `...`
- Rich-Click variant: same structure, may have ANSI codes
- Recurse: `<cli> <sub> --help`

---

## Typer (Python)

Built on Click, uses Rich formatting:

```
                                                                        
 Usage: <cli> [OPTIONS] COMMAND [ARGS]...                               
                                                                        
╭─ Options ──────────────────────────────────────────────────────────────╮
│ --help    Show this message and exit.                                  │
╰────────────────────────────────────────────────────────────────────────╯
╭─ Commands ─────────────────────────────────────────────────────────────╮
│ <cmd>   <description>                                                  │
╰────────────────────────────────────────────────────────────────────────╯
```

**Extraction:**
- Same as Click after stripping box-drawing characters and ANSI
- `sed 's/[│╭╮╰╯─]//g'` then apply Click rules

---

## Argparse (Python)

```
usage: <cli> [-h] [--flag FLAG] {sub1,sub2} ...

<Description>

positional arguments:
  {sub1,sub2}   <description>

options:
  -h, --help    show this help message and exit
  --flag FLAG   <description>
```

**Extraction:**
- Subcommands: `{sub1,sub2,...}` in usage line, or choices under `positional arguments:`
- Options: under `options:` or `optional arguments:` (older Python)
- Subparser detection: `{...}` in usage = has subcommands
- Recurse: `<cli> <sub> -h`

---

## Clap (Rust)

**v3:**
```
<tool> <version>

USAGE:
    <cli> [OPTIONS] [SUBCOMMAND]

OPTIONS:
    -h, --help       Print help
    --flag <VALUE>   <description>

SUBCOMMANDS:
    <cmd>    <description>
```

**v4 (looks like Cobra):**
```
Usage: <cli> [OPTIONS] [COMMAND]

Commands:
  <cmd>  <description>

Options:
  -h, --help     Print help
```

**Extraction:**
- v3: `SUBCOMMANDS:` header (caps) — `^\s{2,4}(\S+)\s{2,}(.+)$`
- v4: `Commands:` header — same regex
- Distinguish from Cobra: version string at top often has Rust-style `<name> <sem-ver>`
- Recurse: `<cli> <sub> --help` or `<cli> help <sub>`

---

## urfave/cli (Go)

```
NAME:
   <cli> - <description>

USAGE:
   <cli> [global options] command [command options]

COMMANDS:
   <cmd>     <description>
   help, h   Shows a list of commands

GLOBAL OPTIONS:
   --flag value    <description> (default: "x")
   --help, -h      show help
```

**Extraction:**
- Subcommands: under `COMMANDS:` — `^\s{3}(\S+)(?:,\s\S+)?\s{2,}(.+)$`
- Flags: under `GLOBAL OPTIONS:` or `OPTIONS:`
- Aliases shown inline: `help, h`
- Recurse: `<cli> <sub> --help` or `<cli> help <sub>`

---

## Commander (Node.js)

```
Usage: <cli> [options] [command]

<Description>

Options:
  -V, --version          output the version number
  -h, --help             display help for command

Commands:
  <cmd> [options] <arg>  <description>
  help [command]         display help for command
```

**Extraction:**
- Subcommands: under `Commands:` — includes arg signatures inline
- Clean extraction: `^\s{2}(\S+)\s.*?\s{2}(.+)$`
- Recurse: `<cli> <sub> --help` or `<cli> help <sub>`

---

## oclif (Node.js)

```
<description>

VERSION
  <cli>/1.2.3 linux-x64 node-v18

USAGE
  $ <cli> COMMAND

COMMANDS
  <cmd>  <description>
```

**Extraction:**
- Subcommands: under `COMMANDS` (no colon)
- May have `TOPICS` section for namespaced commands
- Flags in subcommands: `FLAGS` header (caps)
- Recurse: `<cli> <sub> --help` or `<cli> help <sub>`

---

## picocli (Java)

```
Usage: <cli> [COMMAND]

<Description>

Commands:
  <cmd>  <description>

Options:
  -h, --help      Show this help message and exit.
  -V, --version   Print version information and exit.
```

**Extraction:**
- Similar to Clap v4 / Cobra
- Distinguish: Java stack trace patterns in errors, or `@|bold` markup
- Recurse: `<cli> <sub> --help` or `<cli> help <sub>`

---

## Custom / getopt / no framework

No consistent structure. Heuristic parsing:

**Subcommands:** Look for indented `<word>  <description>` pairs after a
header line. Common headers: `commands:`, `subcommands:`, or just aligned pairs
after a blank line.

**Flags:** Lines matching `^\s+-` — extract: `^\s+(-\w(?:,\s+--\S+)?|--\S+)\s+(<\S+>)?\s{2,}(.+)$`

**Fallbacks when parsing fails:**
1. `man <cli>` → parse SYNOPSIS + DESCRIPTION
2. `<cli> help` (no dashes)
3. `<cli> --help all` (curl-style extended help)
4. Web search: `<cli> command reference documentation`

---

## Universal parsing tips

1. **Strip ANSI first:** `<cli> --help 2>&1 | sed 's/\x1b\[[0-9;]*m//g'`
2. **Merge stderr:** some CLIs print help to stderr — `2>&1`
3. **Disable pagers:** `PAGER=cat NO_COLOR=1 TERM=dumb <cli> --help`
4. **Leaf detection:** no subcommand section in help = leaf command
5. **`--help` vs `-h`:** some CLIs give different output (short vs long)
6. **Plugins:** commands with `*` (Cobra) or `PLUGINS` section — note but don't crawl
7. **Hidden commands:** don't hunt for them unless specifically asked
8. **Version:** check `--version`, `-V`, or `version` subcommand
