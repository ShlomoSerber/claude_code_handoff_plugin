# Design notes

Research date: 2026-09-23. Claude Code 2.1.x.

## 1. Who writes the handoff: the main model, in-context

This is also what Claude Code itself does: `/compact` sends a separate request with the same system prompt, tools and history plus a summarization instruction, on the session model, reading the warm cache. Prompt caches are per model, so a different model cannot reuse them (GitHub issue anthropics/claude-code#96316 asks for a cheaper compaction model precisely because none exists). Anthropic's API compaction likewise uses the request's model.

Options considered:

| Option | Input cost | Fidelity |
|---|---|---|
| Main model, same turn (chosen) | Whole history is already a cache hit (cache reads are 10% of input price on Opus/Sonnet/Haiku, 5% on Opus 5.5, 2.5% on Fable 5.1). Only the ~500-1000 output tokens are new spend. | Highest: the writer holds every nuance of the session. |
| `model: haiku` in the skill frontmatter, no fork | Claude Code docs: a `model:` override without `context: fork` switches model for that one turn, which invalidates the cache, so the whole history is re-read as uncached input. 100k tokens × $1/M (Haiku) = $0.10, versus 100k × $0.50/M cached on Opus 5 = $0.05. The cheap model costs more here. | Lower. ConstraintRot: constraint violations after compaction track the summarizer, not the agent (7-13% with a strong summarizer, 33-93% with a weak one). FaithBench: every model hallucinates in summaries, small open models most. Handoff Tax (arXiv 2608.24358): the stronger model's own record is the valuable artifact; a weaker author's state hurts the resume. |
| `context: fork` subagent reading the transcript `.jsonl` | The forked agent starts with no conversation history (docs). It would have to read the raw transcript, which is 5-20x larger than the useful content (tool results, metadata). | Lowest, and slowest. |

Conclusion: no `model:` field, no fork. The skill runs in the main conversation on the session model. The one cost that matters is output tokens, and the format rules keep those at a few hundred.

## 2. When to clear

Pricing used (Anthropic first-party, 2026-09-23): Opus 5 $5 in / $25 out / $0.50 cache read per MTok; Fable 5.1 $10 / $50 / $0.25; Opus 5.5 $4 / $20 / $0.20; Sonnet 5 $2 / $10 / $0.20; Haiku 4.5 $1 / $5 / $0.10. Cache write is 1.25x input.

Cost of one prompt in Claude Code ≈ (API requests in the turn) × (context size × cache-read price) + new tokens. Every tool call is a request. A prompt that fires 10 tool calls on a 100k context re-reads 1M cached tokens: $0.50 on Opus 5. Context size multiplies everything.

What a reset costs on Opus 5, 100k context:
- The handoff turn: 100k cached read ($0.05) + ~1k output ($0.025).
- First turn after `/clear`: the conversation layer of the cache rebuilds. ~10k of system prompt, CLAUDE.md and handoff written to cache: ~$0.06.
- Total ≈ $0.14, about three cached 100k reads. From the fourth request on, the small context is ahead, and the savings repeat on every later prompt.

At 30k context the same reset costs ~$0.10 and saves ~$0.01 per request, so it needs ~10 requests to break even. Under ~20k it does not pay.

The costs that do not show in the bill:
- A summary drops things. Anthropic: "overly aggressive compaction can result in the loss of subtle but critical context whose importance only becomes apparent later."
- Constraints in particular. ConstraintRot (arXiv 2606.22528, 1,323 episodes, 7 model families): violations of in-context user policies go from 0% with full context to 30% pooled after compaction, up to 59%. When the constraint survives the summary verbatim, violations stay at 0%. Fix: quote constraints verbatim and exempt them from compression. This is why `CONSTRAINTS` and `LAST_REQUEST` are verbatim and never cut.
- Failure history. Manus: "keep the wrong stuff in"; failed approaches are the most expensive thing to rediscover. This is the `REJECTED` section.
- Over-compression backfires. A pre-registered RCT on Sonnet 4.5 prompts (arXiv 2603.23525): moderate compression saved 28% cost; extreme compression raised cost 1.8% because outputs expanded. Hence the 300-800 word target instead of a 200-token cap.

Where the evidence agrees on the trigger:
- Anthropic's Claude Code best practices: `/clear` between unrelated tasks; a clean session with a better prompt beats a long session with accumulated corrections; but "sometimes you should let context accumulate because you're deep in one complex problem and the history is valuable."
- Chroma's Context Rot study (18 models): a focused ~300-token prompt beat the full ~113k transcript on every model. Degradation starts well before the window is full.
- Manus: a 1M model "performs well only until < 256k tokens"; rot threshold around 128k.

Rules that follow, for a 1M-window session model (`opus[1m]` never auto-compacts before ~967k, so nothing else will shrink the context for you):
- Clear at task boundaries. Next prompt starts something new → `/handoff`, `/clear`.
- Inside a task, keep going. Mid-debugging state is expensive to rebuild and easy to lose.
- Under ~20-30k tokens, do not bother. Check with `/context`.
- Above ~100k, or when answers start ignoring earlier instructions, clear even mid-task with a `/handoff next: …` note.
- Before a break longer than the cache TTL (1 hour on Pro/Max, 5 minutes on API billing), always hand off. Re-warming 100k of cold context costs full input price ($0.50 on Opus 5) versus $0.06 for a fresh 10k.

`/compact [instructions]` is the built-in alternative. It uses the session model and the warm cache, so its cost is the same as `/handoff`. Reasons to prefer `/handoff`: you control the size (compaction summaries run several thousand tokens and the built-in schema keeps code snippets), the note persists on disk and survives a crash, and the next session carries only a 40-token pointer until you ask for the body. `/rewind` is cheaper than both when you only want to abandon a wrong path: it truncates back to an already-cached prefix.

## 3. Format for an AI reader

Principles applied in `skills/handoff/SKILL.md`:

- State, not narrative. The reader needs where things are, not how they got there.
- Fixed section keys in a fixed order. The reader can skip to `NEXT` without parsing.
- Terse markdown, not JSON or YAML. Benchmark on Claude's tokenizer (120 files, Haiku 4.5 / Sonnet 4.6 / Opus 4.6): plain text −57% and Markdown −53% tokens versus JSON, YAML only −32%. Sonnet and Opus were format-invariant in accuracy, so the format is pure cost. `KEY:` plus `-` bullets is the cheapest structure that still parses reliably.
- No invented shorthand. Under a BPE tokenizer, mangled words fall back to byte-level pieces: one controlled test that deleted 25% of characters made the text 22% smaller in bytes and 23% larger in tokens. Dropping articles, filler and whole redundant sentences is free; mangling words is not. LLMLingua-style token dropping works, but it needs a trained classifier; naive stop-word removal only reached 1.3x.
- `path:line` instead of code. The file is on disk; the pointer is enough.
- English body, verbatim quotes. English is the most token-dense language for Claude's tokenizer; user constraints keep their original wording because that wording is the constraint.
- Never drop: hard constraints, `REJECTED` approaches (the single most expensive thing to lose, because the next session will retry them), `NEXT`.
- Tag epistemic status: `(unverified)`, `(assumed)`. A summary that presents guesses as facts causes the next session to build on them.
- Size cap. 300-800 words, hard cap 1200, with an explicit order of what to cut first.

## 4. Storage

`~/.claude/projects/<encoded-cwd>/handoff/`, beside Claude Code's own transcripts. Same encoding as the transcripts (non-alphanumeric → `-`, verified against the existing directories), computed by `scripts/handoff-paths.sh`. `latest.md` is overwritten; a timestamped copy is kept, last 10.

Not used: Claude Code's auto memory (`…/memory/MEMORY.md`). That file is loaded into every session automatically, which is the opposite of the goal. The handoff must cost nothing until asked for.

## 5. Delivery to the next session

A `SessionStart` hook (`startup|resume|clear`) prints one line with path, age and approximate size, plus "read it only when asked". About 40 tokens when a handoff exists, zero when not. The body never enters context unprompted, so a stale handoff from last week cannot hijack an unrelated session.

## 6. Why `/handoff-clear` still needs you to type `/clear`

Checked in the Claude Code docs (skills, hooks reference, keybindings, sessions) and in the 2.1.280 binary: no skill, hook output field or keybinding action can run `/clear` or submit a prompt. Hook outputs are limited to `additionalContext`, `decision: block`, `systemMessage`, `updatedInput` (tool input only) and `continue/stopReason`. Keybinding actions include `chat:clearInput` and `chat:clearScreen`, not a conversation clear. `/clear` takes no prompt argument.

What does exist: `SessionStart` fires with `source: clear`, and its stdout lands in context before the first prompt. So `/handoff-clear` parks the next prompt in `pending-prompt.txt`; the hook prints `Look at the handoff in <path>. The following is the users next prompt: <text>` once and deletes the file. The user types `/clear` and any acknowledgement. Two guards: the parked prompt expires after 2 hours, and `source: resume` leaves it untouched, so an old prompt cannot fire in an unrelated session.

## 7. Status line

`statusLine` in settings.json receives a JSON document on stdin with `context_window.current_usage.{input_tokens, cache_creation_input_tokens, cache_read_input_tokens}`, `context_window_size` and `used_percentage`. Tokens in context now = the sum of the three `current_usage` fields (the last request's fresh input plus cache writes plus cache reads). `scripts/statusline.sh` prints `context <used>/<window> <pct>%`, green under 60k, yellow to 100k, red above, with the `/handoff-clear` suggestion appended past the threshold. The built-in yellow warning ("Context low (N% remaining)") only appears near auto-compact, which on a 1M model is ~967k; hence the custom line.

## Sources

Anthropic
- Effective context engineering for AI agents: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Claude Code best practices (context management): https://code.claude.com/docs/en/best-practices
- Claude Code prompt caching, `/clear`, `/compact`, `/rewind` costs: https://code.claude.com/docs/en/prompt-caching · https://code.claude.com/docs/en/costs
- Claude Code skills reference (frontmatter, `model:`, `context: fork`, `${CLAUDE_SESSION_ID}`): https://code.claude.com/docs/en/skills
- Claude Code sessions (transcript location and encoding): https://code.claude.com/docs/en/sessions
- Claude Code hooks (SessionStart matchers, stdout injection): https://code.claude.com/docs/en/hooks
- Claude Code plugins and marketplaces: https://code.claude.com/docs/en/plugins · https://code.claude.com/docs/en/plugin-marketplaces
- Claude Code auto-compact thresholds: https://code.claude.com/docs/en/model-config
- API compaction (same-model summarization): https://platform.claude.com/docs/en/build-with-claude/compaction-on-demand
- Pricing: https://platform.claude.com/docs/en/about-claude/pricing
- Multi-agent research system (handoffs, subagent summaries): https://www.anthropic.com/engineering/multi-agent-research-system
- Lessons from building Claude Code: prompt caching is everything: https://claude.dev/blog/lessons-from-building-claude-code-prompt-caching-is-everything/
- Compaction model issue: https://github.com/anthropics/claude-code/issues/96316

Studies
- Chroma, Context Rot: https://www.trychroma.com/research/context-rot
- ConstraintRot / Governance Decay: https://arxiv.org/abs/2606.22528
- Slipstream (summary validation against forward intent): https://arxiv.org/abs/2605.08580
- Handoff Tax: https://arxiv.org/abs/2608.24358
- Compression RCT on Sonnet 4.5: https://arxiv.org/abs/2603.23525
- Compression and execution instability: https://arxiv.org/abs/2608.06503
- LLMLingua / LLMLingua-2: https://github.com/microsoft/LLMLingua · https://arxiv.org/abs/2403.12968
- FaithBench: https://aclanthology.org/2025.naacl-short.38.pdf
- Format token benchmark on Claude's tokenizer: https://webmaster-ramos.com/blog/yaml-vs-md-benchmark-claude-api
- Tokens-per-byte trap (character-level compression adds tokens): https://dev.to/vainamoinen/the-tokens-per-byte-trap-character-level-compression-adds-tokens-3l65

Practice
- Manus, Context Engineering for AI Agents: https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus · https://www.philschmid.de/context-engineering-part-2
- Cognition, Don't Build Multi-Agents: https://cognition.com/blog/dont-build-multi-agents
- Claude Code compaction prompt (reverse-engineered): https://github.com/Yuyz0112/claude-code-reverse/blob/main/results/prompts/compact.prompt.md
- Handoff templates: https://github.com/sidorovanthon/handoff-prompt · https://github.com/REMvisual/claude-handoff · https://www.jdhodges.com/blog/ai-session-handoffs-keep-context-across-conversations/
