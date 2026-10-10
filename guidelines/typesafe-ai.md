# TypeSafe AI Decision-System Guideline

Precedence follows `general.md` §2. This companion covers building or changing
a TypeSafe System One workflow.

Jev returns typed probabilistic judgments, not generated prose, verified facts,
or permission to perform an action. Code owns the workflow and its
consequences.

## 1. Choose the Right Boundary

- Start with the product action or user-visible result; identify the semantic
  judgment needed to reach it. Keep exact lookups, calculations, validation,
  authorization, and execution in ordinary code.
- Use Jev for bounded interpretation of unstructured text or structured
  application state: routing, selecting candidates, scoring, verification, or
  extracting one value from a known candidate set.
- Do not use a model call where deterministic rules already answer the question.
  Do not ask Jev to produce free-form text, an arbitrary ID, money amount, date,
  or URL. Retrieve possible values first, select one, then validate and normalize
  it in code.
- Separate the decision adapter (state, questions, typed answers) from the
  application policy (thresholds, permissions, branching) and side-effecting
  handlers. Do not bury business rules in question wording alone.
- For high-impact operations, the model may suggest an action; code MUST still
  check current state, authorization, invariants, and idempotency before acting.

## 2. Build State and Questions

- Supply only relevant, current facts. Prefer a JSON object with named fields
  for related text, records, candidate sets, and policy context; a string is
  sufficient for a single short text. Keep observed facts distinct from inferred
  judgments.
- Treat source content as untrusted data, not instructions to the application.
  Minimize or redact personal, medical, financial, and secret data before sending
  it. Never send API keys in state or question text.
- Ask one coherent judgment per question. Place the actual question in
  `instructions` and define possible answers in `criteria`. Question IDs are
  application keys, not model instructions; give the model complete meaning in
  the question itself. Refer to named state fields explicitly.
- Use **Choice** for one answer from a defined set. Include `other`/`none` when
  the candidates may not cover the input; verify candidate coverage before
  making a selection. A Choice cannot invent a missing candidate.
- Use **Noul** for the probability that a yes/no condition holds. For multiple
  independently applicable labels, use separate Nouls rather than forcing one
  Choice. A Noul near 0.5 means uncertainty between yes and no, not medium
  intensity; it has no separate `confidence` field.
- Use **Score** for an ordered degree or severity. Describe each level
  independently and concretely; `score` can fall between levels. Do not use a
  Noul probability as an intensity scale.
- Keep options mutually understandable and level order stable. Put contrasts,
  exclusions, or brief examples into structured criteria when they improve the
  distinction. Test question wording on ambiguous and adversarial cases.

## 3. Compose Decisions in Code

- Batch independent questions about the same state in one request, including
  useful speculative branch questions. Each question is evaluated independently
  and cannot see another answer; consume only the answers relevant to the chosen
  branch. Use a later request when new evidence or an earlier answer is needed
  to define the next state or options.
- Read both the selected Choice/Score result and its distribution. Choice and
  Score `confidence` summarize concentration across options or levels; it is
  not a guarantee of factual correctness or action safety.
- Keep decision thresholds, weights, vetoes, and fallbacks in versioned code.
  Choose thresholds based on real evaluation data and the cost of each error,
  not a cookbook number. An “any serious violation” rule needs a separate veto,
  not only a weighted average.
- If the state lacks evidence, the model is uncertain, or a required candidate
  is missing, request clarification, collect evidence, or escalate to human or
  reasoning-model review. Do not force an answer to make an automation succeed.
- Before a state-changing action, recheck that the underlying facts are still
  current. Design retries and duplicate deliveries to be safe; use stable
  idempotency keys for effects such as transfers, notifications, or account
  changes.

## 4. Integrate and Operate Safely

- Read the current [documentation index](https://docs.typesafe.ai/llms.txt),
  [API reference](https://docs.typesafe.ai/api.md), and the relevant
  [SDK](https://docs.typesafe.ai/sdk.md) before coding. Prefer the installed SDK
  and its types; do not assume examples for one SDK version match another.
- Keep `TYPESAFE_API_KEY` server-side. Never expose it in a browser bundle,
  mobile app, logs, tests, or error responses, and never set
  `dangerouslyAllowBrowser: true`. Put calls behind a server-owned boundary.
- Use the SDK's built-in retry policy (`retry` in the client config or per
  call). It already retries 408, 429, and 5xx with backoff and honors
  `retry-after`; do not wrap it in another retry loop. Set a per-attempt
  `timeout` and remember there is no total retry budget, so bound the caller with
  an `AbortSignal` when latency matters.
- Never use `logLevel: "debug"` (or `TYPESAFE_LOG_LEVEL=debug`) outside local
  debugging: it logs request bodies, including state, without redaction.
- Log the response `model` field with each decision. It reports the versioned
  model that answered even when the request used an alias.
- Define what happens when the service times out, rejects a request, or returns
  no usable result. Fail closed for sensitive actions; use a safe deterministic
  fallback or manual review rather than silently choosing an option.
- Measure request tokens, cost, latency, error rate, review rate, and downstream
  outcomes. Batch only questions that the workflow may actually need; extra
  questions consume tokens even when ignored.
- Version the model selection, question definitions, criteria, and policy
  thresholds so a regression can be traced. Treat `jev-latest` as a moving
  alias; pin a supported version when reproducibility matters and evaluate
  changes before switching.

### Facts as of jev-1.13 (verified 2026-10-10)

- Packages: JavaScript `@typesafe-ai/sdk` (0.6.x, Node 20 or newer); Python
  `typesafe_sdk` (`from typesafe_sdk import TypeSafeClient`).
- JavaScript API: `new TypeSafeClient(config)` and
  `client.systemOne({ state, questions })`, with the question helpers `choice()`,
  `noul()`, and `score()`. Config fields: `apiKey`, `baseURL`, `defaultModel`,
  `logLevel`, `retry`, `timeout` (10000 ms per attempt by default).
- Environment: `TYPESAFE_API_KEY`, `TYPESAFE_BASE_URL`,
  `TYPESAFE_DEFAULT_MODEL` (default `jev-latest`), `TYPESAFE_LOG_LEVEL`
  (default `warn`).
- HTTP: `POST https://api.typesafe.ai/v1/systemone` with
  `Authorization: Bearer <API_KEY>`. The response carries `model`, `answers`
  keyed like the questions, and `usage`.
- Limits: Choice up to 255 options; Score 2 to 10 levels; 64k tokens per
  request and 32k for `state` plus the longest question. Limits can change.
- Models: `jev-1.13.0` is current; `jev-latest` and `jev-preview` are moving
  aliases.
- References: [JavaScript SDK](https://docs.typesafe.ai/sdk/javascript.md),
  [API](https://docs.typesafe.ai/api.md),
  [Models](https://docs.typesafe.ai/models.md).

## 5. Test the Decision System

- Keep a representative, redacted evaluation set with clear positives,
  negatives, no-match cases, ambiguous cases, missing evidence, and changes in
  state between judgment and action. English is the primary training language
  and other languages are handled less accurately, so Indonesian and mixed-language
  inputs MUST have their own labeled cases before release.
- Test the deterministic policy with fixed answer distributions: correct
  branch, threshold boundaries, vetoes, fallback, timeout, stale state,
  idempotency, and rejected/invalid results. These tests MUST NOT require a live
  API key.
- Evaluate the live model separately on labeled cases before release and after
  changing questions or model versions. Track calibration and error costs, not
  just overall accuracy; inspect the state, candidate coverage, prompt, and
  answer distributions for failures.
- Do not hard-code outcomes for test examples or infer accuracy from type-safe
  responses. Typed outputs prevent malformed answer shapes, not wrong judgments.

## Sources

- [Introducing System One Models & Jev](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
- [How to build with TypeSafe](https://docs.typesafe.ai/concepts/how-to-build-with-system-one.md)
- [State](https://docs.typesafe.ai/concepts/state.md), [primitives](https://docs.typesafe.ai/primitives.md), and [confidence](https://docs.typesafe.ai/confidence.md)
