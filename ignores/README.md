# Coding-Agent Ignore Files

`agent.ignore` is the canonical managed block installed into the selected
agent-specific ignore file with `--ignore-agent <agent>`. The patterns exclude
secrets, credentials, dependencies, generated output, caches, local state,
logs, temporary files, and compiled binaries while keeping source,
documentation, migrations, lockfiles, public assets, and `.agents` guidelines
available.

The installer can create one of these project-root files:

| `--ignore-agent` value | File | Consumer |
| --- | --- | --- |
| `cursor` | `.cursorignore` | Cursor |
| `codex` | `.ignore` | OpenCode and OpenAI Codex file discovery |
| `gemini` | `.geminiignore` | Gemini CLI |
| `aider` | `.aiderignore` | Aider |
| `continue` | `.continueignore` | Continue |
| `cline` | `.clineignore` | Cline; currently supported but being deprecated |
| `windsurf` | `.codeiumignore` | Windsurf |
| `roo` | `.rooignore` | Roo Code and compatible forks |
| `junie` | `.aiignore` | JetBrains Junie and AI Assistant |

OpenCode does not natively support `.opencodeignore`; use `.ignore`. There is no
authoritative native support for `.claudeignore`, `.codexignore`,
`.copilotignore`, or `.ampignore`, so the installer does not create misleading
files. GitHub Copilot content exclusion is configured in GitHub repository or
organization settings. Amp intentionally does not implement an ignore file.

These files use gitignore-style patterns, but enforcement differs by agent and
is not a security boundary. Terminal commands, plugins, MCP tools, explicit file
mentions, or agent-specific modes may bypass ignore rules. Keep secrets outside
the repository, use least-privilege credentials, and rely on filesystem or
sandbox permissions when access must be prevented.

The managed block is bounded by:

```text
# AI-GUIDELINES-IGNORE:BEGIN
...
# AI-GUIDELINES-IGNORE:END
```

The installer preserves custom content outside this block and refreshes only the
managed portion. Add project-specific exclusions before or after the block.

## Support References

- [Cursor ignore-file reference](https://cursor.com/docs/reference/ignore-file)
- [OpenCode file-list implementation](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/server/routes/instance/httpapi/handlers/file.ts)
- [Codex file-search behavior](https://github.com/openai/codex/blob/main/codex-rs/file-search/README.md)
- [Gemini CLI ignore-file reference](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/gemini-ignore.md)
- [Aider ignore configuration](https://aider.chat/docs/config/aider_conf.html)
- [Continue codebase ignore reference](https://github.com/continuedev/continue/blob/main/docs/reference/deprecated-codebase.mdx)
- [Cline ignore-file reference](https://github.com/cline/cline/blob/main/docs/customization/clineignore.mdx)
- [Windsurf ignore-file reference](https://docs.windsurf.com/context-awareness/windsurf-ignore)
- [Roo Code ignore-file reference](https://roocodeinc.github.io/Roo-Code/features/rooignore)
- [JetBrains Junie `.aiignore` reference](https://junie.jetbrains.com/docs/junie-ide-plugin.html#restrict-access-to-files-or-folders)
- [GitHub Copilot content exclusion](https://docs.github.com/en/copilot/how-tos/configure-content-exclusion/exclude-content-from-copilot)
- [Amp's ignore-file policy](https://ampcode.com/notes/fif#where-is-the-ampignore-file)
