# Copilot Skills & Agents

Portable collection of VS Code Copilot skills and agents. No Azure, ADO, or enterprise dependencies — works on any machine with VS Code and GitHub Copilot.

## Contents

- **46 skills** in `skills/` — domain knowledge auto-injected by description matching
- **5 agents** in `agents/` — specialized personas invokable via `@AgentName`

## Installation

### Skills

Copy skill folders to your Copilot skills directory:

```powershell
# Windows
Copy-Item .\skills\* "$HOME\.copilot\skills\" -Recurse -Force

# macOS/Linux
cp -r ./skills/* ~/.copilot/skills/
```

### Agents

Copy agent files to your VS Code prompts directory:

```powershell
# Windows
Copy-Item .\agents\* "$env:APPDATA\Code\User\prompts\" -Force

# macOS
cp ./agents/* "$HOME/Library/Application Support/Code/User/prompts/"

# Linux
cp ./agents/* "$HOME/.config/Code/User/prompts/"
```

## Skills

### Engineering Methodology (from [superpowers](https://github.com/obra/superpowers))
| Skill | Trigger |
|-------|---------|
| brainstorming | Before any creative work — features, components, functionality |
| writing-plans | When you have a spec, before touching code |
| executing-plans | When you have a plan to execute with review checkpoints |
| test-driven-development | Before writing any implementation code |
| systematic-debugging | When hitting any bug or test failure |
| subagent-driven-development | Executing plans with independent tasks |
| dispatching-parallel-agents | 2+ independent tasks with no shared state |
| requesting-code-review | After completing tasks, before merge |
| receiving-code-review | When responding to review feedback |
| verification-before-completion | Before claiming work is done |
| finishing-a-development-branch | After tests pass, deciding how to integrate |
| using-git-worktrees | Starting isolated feature work |
| writing-skills | Creating or editing SKILL.md files |
| using-superpowers | Meta-skill: check skills before every response |

### Orchestration (from [claude-mem](https://github.com/thedotmack/claude-mem))
| Skill | Trigger |
|-------|---------|
| cm-make-plan | Create phased implementation plans |
| cm-do | Execute phased plans using subagents |

### Document Generation (from [anthropics/skills](https://github.com/anthropics/skills))
| Skill | Trigger |
|-------|---------|
| docx | Create/read/edit Word documents (.docx) |
| pptx | Create/edit PowerPoint presentations |
| pdf | Read/create/merge/split/OCR PDFs |
| xlsx | Read/create/edit spreadsheets |
| doc-coauthoring | Co-authoring documentation workflows |

### Design & Visual (from [anthropics/skills](https://github.com/anthropics/skills))
| Skill | Trigger |
|-------|---------|
| canvas-design | Create visual art as PNG/PDF |
| frontend-design | Build production-grade web UIs |
| algorithmic-art | Generative art with p5.js |
| theme-factory | 10 pre-built visual themes for any artifact |

### Developer Tools (from [anthropics/skills](https://github.com/anthropics/skills))
| Skill | Trigger |
|-------|---------|
| claude-api | Build apps with Claude API / Anthropic SDK |
| mcp-builder | Create MCP servers (Python/Node) |
| webapp-testing | Test web apps with Playwright |
| skill-creator | Create/evaluate/optimize skills |

### Obsidian (from [obsidian-skills](https://github.com/anthropics/skills))
| Skill | Trigger |
|-------|---------|
| obsidian-cli | Interact with Obsidian vaults via CLI |
| obsidian-markdown | Obsidian-flavored markdown (wikilinks, callouts) |
| obsidian-bases | Obsidian Bases (.base files) |
| json-canvas | JSON Canvas files (.canvas) |
| defuddle | Extract clean markdown from web pages |

### Accessibility Testing
| Skill | Trigger |
|-------|---------|
| axe-core-testing | Automated WCAG compliance scanning |
| bypass-blocks-testing | WCAG 2.4.1 bypass blocks |
| focus-order-testing | WCAG 2.4.3 focus order |
| heading-levels-testing | WCAG 1.3.1 heading levels |
| image-function-testing | WCAG 1.1.1 non-text content |
| instructions-testing | WCAG 1.3.1, 2.5.3 widget labels |
| keyboard-navigation-testing | WCAG 2.1.1 keyboard |
| link-purpose-testing | WCAG 2.4.4 link purpose |
| no-missing-headings-testing | WCAG 1.3.1, 2.4.6 missing headings |
| reflow-testing | WCAG 1.4.10 reflow |
| report-templates | Accessibility test result templates |
| ui-components-contrast-testing | WCAG 1.4.3 / 1.4.11 contrast |

## Agents

| Agent | Purpose |
|-------|---------|
| **Planner** | Senior Tech Lead — breaks complex work into structured plans |
| **Coder** | Senior Engineer — implements from task specifications |
| **Tester** | QA Engineer — writes and runs automated tests |
| **PromptWriter** | Creates/refines .prompt.md files with variable interpolation |
| **AgentBuilder** | Designs .agent.md and SKILL.md files, converts Claude Code agents |

## Sources

| Repo | What we took |
|------|-------------|
| [obra/superpowers](https://github.com/obra/superpowers) | 14 methodology skills |
| [anthropics/skills](https://github.com/anthropics/skills) | 12 production skills (doc gen, design, dev tools) |
| [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) | 2 orchestration skills |
| Obsidian skills | 5 Obsidian skills |
| Custom | 5 agents (Planner, Coder, Tester, PromptWriter, AgentBuilder) |

## License

Individual skills retain their original licenses. Check `LICENSE.txt` in each skill directory.
