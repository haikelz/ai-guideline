# Next.js App Router Coding-Agent Guideline

This document is the framework-specific companion to the JavaScript and TypeScript engineering guideline. Apply both, together with repository instructions and product contracts. This document assumes the App Router; do not silently introduce Pages Router conventions.

The terms **MUST**, **SHOULD**, and **AVOID** are normative. When a repository convention conflicts with a suggestion here, preserve the established convention unless it is unsafe, broken, or the task explicitly changes it.

## 1. Scope and Version Discovery

Before editing, an agent **MUST** establish facts rather than rely on remembered Next.js behavior:

1. Read instruction files, the root and application `package.json` files, lockfile, workspace configuration, `next.config.*`, TypeScript configuration, lint/format configuration, test configuration, and relevant environment examples. Never open populated secret files.
2. Determine the installed versions of Next.js, React, the package manager, Node.js, and relevant libraries from manifests and the lockfile. Major versions affect request APIs, caching, middleware naming, Server Actions, and build behavior.
3. Determine whether the application uses `src/app` or `app`, whether it is standalone or in a monorepo, and which project owns the target.
4. Inspect neighboring routes, providers, services, schemas, components, tests, and import aliases before choosing placement.
5. Check whether request APIs such as `params`, `searchParams`, `cookies()`, and `headers()` are asynchronous in the installed version. Use the installed API, not compatibility casts.
6. Check official documentation for the installed major/minor version when behavior is uncertain or recently changed. In particular, newer versions may rename `middleware.ts` to `proxy.ts`; follow the installed version and existing repository.
7. Trace cache tags, query keys, redirects, authorization, metadata, and public contracts before changing them.

### MUST

- Make the smallest complete change and preserve the current package manager and router.
- Treat experimental flags as version-bound. Verify that each remains supported before adding or retaining it.
- Keep framework-generated files and build output out of manual edits.

### SHOULD

- Record version-sensitive assumptions in code only when they are not obvious from types or configuration.
- Prefer stable framework APIs over experimental features unless requirements demand otherwise.

### AVOID

- Upgrading Next.js, React, lockfiles, or unrelated dependencies as part of a feature fix.
- Copying examples from a different Next.js major version.
- Using deprecated `next lint`; invoke the repository's actual linter directly when required by the installed version.

## 2. Project and Monorepo Placement

A common ownership model is:

```text
apps/web/
  src/app/                 route tree and framework files
  src/components/ui/       domain-free accessible primitives
  src/components/common/   shared application composition
  src/features/<feature>/  feature UI, schemas, hooks, and client queries
  src/server/              server-only use cases, repositories, auth
  src/services/            typed transport clients
  src/lib/                 focused framework-neutral utilities
packages/
  ui/                      genuinely shared UI
  contracts/               shared schemas or generated API contracts
  config/                  shared tool configuration
```

### MUST

- Put code in the project that owns its runtime and deployment. Use workspace packages only for capabilities genuinely shared by multiple projects.
- Keep route files thin: URL contract, metadata, request parsing, server composition, and route-specific boundaries.
- Respect dependency direction: routes/features may depend on shared primitives; primitives MUST NOT depend on routes or domain features.
- Mark server-only modules with `import "server-only"` when an accidental client import would expose credentials or privileged behavior.
- Configure package transpilation, exports, and task dependencies explicitly when a workspace package needs them.

### SHOULD

- Colocate feature-private components near the feature; use `_components` or `_lib` inside a route only when the code is truly route-private.
- Expose narrow package entry points instead of importing package internals.
- Keep shared configuration packages free of application runtime assumptions.

### AVOID

- A universal `utils.ts`, giant barrel files, or a shared package containing one application's business logic.
- Deep imports across application boundaries.
- Adding libraries to the workspace root when only one app uses them.

## 3. App Router Structure

### 3.1 Segments and special files

- `page.tsx` makes a segment publicly reachable.
- `layout.tsx` persists across navigation and owns stable shared structure.
- `template.tsx` creates a new instance on navigation; use it only when remount semantics are intentional.
- Parenthesized route groups organize routes and select layouts without changing the URL.
- Dynamic segments use `[id]`, catch-all segments use `[...parts]`, and optional catch-all segments use `[[...parts]]`.
- Parallel and intercepting routes are advanced navigation tools, not default organization mechanisms.

### MUST

- Provide one root layout with `<html>` and `<body>`.
- Keep each `page.tsx` and `layout.tsx` a Server Component unless client behavior is truly required.
- Validate dynamic segments before use and call `notFound()` for absent resources when a 404 is the correct contract.
- Ensure route groups do not accidentally create two pages resolving to the same URL.
- Use a layout for persistent navigation or providers and a template only for deliberate reset/re-entry behavior.

### SHOULD

- Use route groups to separate layout/auth concerns, not merely to shorten imports.
- Prefer ordinary nested routes before parallel/intercepting routes. Use interception for URL-addressable modal navigation that also has a full-page fallback.
- Place providers as deep as practical so static server-rendered regions remain outside client boundaries.

### AVOID

- Putting all application providers, data, and interactivity in the root layout.
- Reading pathname or search state merely to recreate layout routing that the segment tree can express.
- Using `template.tsx` as a substitute for fixing stale local state.

## 4. Server and Client Boundaries

Server Components are the default. They may fetch data, access server configuration, and render Client Components. Client Components may not import Server Components as modules, but they may receive rendered server content through serializable props such as `children`.

### MUST

- Add `"use client"` only at the smallest interactive entry point that needs state, effects, event handlers, context, or browser APIs.
- Pass only React-serializable values across the server/client boundary. Convert database classes, `Date`, `Map`, errors, and provider responses into explicit view models where needed.
- Keep secrets, privileged clients, filesystem access, and server SDKs out of client dependency graphs.
- Treat every Client Component input and every Server Action argument as untrusted.
- Import browser-only heavy libraries dynamically, with server rendering disabled only when the library truly cannot render on the server.

### SHOULD

- Fetch on the server when data is needed for first render, SEO, or authorization and does not require live client interaction.
- Pass minimal initial data rather than large raw responses.
- Use composition to keep static markup server-rendered around small client islands.

### AVOID

- Marking a page or layout client-side to solve one interactive control.
- Using `useEffect` to fetch initial page data that a Server Component can fetch.
- Importing server-only modules through a barrel that is also consumed by clients.
- Disabling hydration warnings globally or using them to hide nondeterministic rendering.

## 5. Parameters, Search Parameters, and Navigation

For versions with asynchronous route props, use the generated or explicit promise types:

```tsx
type PageProps = {
  params: Promise<{ itemId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function Page({ params, searchParams }: PageProps) {
  const { itemId } = await params;
  const rawQuery = await searchParams;
  const query = listQuerySchema.parse(rawQuery);
  const item = await getItem(itemId);

  if (!item) notFound();
  return <ItemView item={item} query={query} />;
}
```

Use the synchronous prop form only when that is the installed API.

### MUST

- Runtime-validate and deliberately coerce route and query input. Account for repeated query keys (`string[]`) and missing values.
- Use `useSearchParams`, `usePathname`, and `useRouter` only in Client Components.
- Use `redirect()`/`permanentRedirect()` for server navigation and `<Link>` for user navigation.
- Preserve unrelated query parameters when changing one filter unless the UX explicitly resets them.
- Encode user-controlled path and query values with framework/URL APIs; never concatenate unsafe redirect destinations.

### SHOULD

- Keep shareable filters, pagination, sort, selected tabs, and search in the URL.
- Use a typed URL-state library if already installed and consistently adopted.
- Debounce replace-navigation for free-text search and use push-navigation for meaningful history steps.

### AVOID

- Mirroring URL parameters into local state with effects.
- Treating `searchParams` as a plain object across versions without checking its contract.
- Open redirects. Allow only local paths or an explicit origin allowlist.

## 6. Metadata, Fonts, and Images

### MUST

- Define global defaults in root `metadata`; use static `metadata` or `generateMetadata` near the owning route.
- Ensure titles, canonical URLs, robots directives, Open Graph data, and social images reflect the deployed environment and page visibility.
- Use `next/font` for supported local or hosted fonts and apply its generated class/variable without introducing layout shift.
- Use `next/image` for content and optimized raster images. Supply meaningful `alt`, intrinsic dimensions or `fill` with a sized parent, and a correct `sizes` value.
- Use empty `alt=""` for decorative images, not filenames.
- Restrict remote image patterns to required protocols, hosts, ports, and path prefixes.

### SHOULD

- Generate route metadata from the same validated data used by the page and rely on request memoization where supported.
- Mark only true above-the-fold largest-content images as priority/preload candidates.
- Use SVG or CSS for simple icons and decoration; use the established icon library.

### AVOID

- Client-side metadata mutation, duplicate `<head>` tags, broad remote image wildcards, or priority on every image.
- Raw `<img>` for normal content merely to bypass image configuration.
- Embedding large base64 assets in components.

## 7. Loading, Errors, Not Found, and Suspense

### MUST

- Use `loading.tsx` or explicit `<Suspense>` boundaries where streaming improves perceived performance.
- Make fallbacks match final geometry closely enough to avoid layout shift and expose accessible loading status when appropriate.
- Implement `error.tsx` as a Client Component and provide a meaningful retry through its `reset` callback when recovery is possible.
- Use `global-error.tsx` only for root failures and include its own `<html>` and `<body>` when required by the installed version.
- Use `not-found.tsx` and `notFound()` for missing resources, not generic caught errors.
- Log/report unexpected errors server-side while showing safe user-facing copy.

```tsx
"use client";

export default function ErrorBoundary({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <section role="alert">
      <h2>Something went wrong</h2>
      <button type="button" onClick={reset}>Try again</button>
    </section>
  );
}
```

### SHOULD

- Place Suspense around the slow subtree, not around the whole page by default.
- Separate initial loading, background refresh, empty, unauthorized, and error states.
- Let expected domain outcomes use typed return values; reserve thrown errors for exceptional failures and framework control flow.

### AVOID

- Catching `redirect()` or `notFound()` in broad `try/catch` blocks.
- Empty spinners with no context, page-wide blocking for one widget, or leaking error messages/stacks.
- Calling `reset()` without fixing or refetching the failing dependency.

## 8. Middleware, Authentication, and Authorization

Use the framework entry filename appropriate to the installed version (`middleware.ts` or its successor). This layer runs broadly and often in a constrained runtime.

### MUST

- Keep middleware/proxy logic lightweight: routing, locale, coarse session presence checks, safe redirects, and headers.
- Configure a precise matcher that excludes static assets, image optimization, metadata files, and unrelated endpoints.
- Verify session integrity with a runtime-compatible mechanism. Never trust an unsigned role or user identifier cookie.
- Enforce authorization again at every privileged data access, Route Handler, and Server Action. UI hiding and middleware redirects are not authorization.
- Derive actor identity from verified server auth context, not submitted fields.
- Use `httpOnly`, `secure` in production, appropriate `sameSite`, scoped `path`, expiry, and CSRF protection for cookie-based mutation flows.
- Return 401 for unauthenticated API access and 403 for authenticated but unauthorized access; use redirects primarily for document navigation.

### SHOULD

- Centralize session retrieval and authorization policies in server-only modules.
- Preserve a validated local return URL through login flows.
- Use a Node runtime server boundary when auth libraries or cryptography are not edge-compatible.

### AVOID

- Database calls, large dependencies, or full permission loading on every middleware match.
- Capturing cookies at module initialization.
- Storing sensitive bearer tokens in `localStorage`.
- Treating middleware, disabled buttons, or hidden links as sufficient access control.

## 9. Route Handlers and Server Actions

Choose the boundary according to consumers:

- A Route Handler is appropriate for public/internal HTTP contracts, webhooks, callbacks, downloads, and non-React clients.
- A Server Action is appropriate for mutations initiated by this React application and progressive-enhancement forms.
- Neither boundary should contain the core business use case.

### MUST

- Validate params, query, headers, body, and form data at the boundary; impose body/file size and content-type limits.
- Authenticate and authorize before privileged work.
- Delegate to a server-only service/use case, map known failures to intentional responses, and hide internal errors.
- Use correct status codes and response headers. Set content type, cache policy, content disposition, and CORS only as required.
- Verify webhook signatures against the raw body before parsing or acting; make retries idempotent.
- Validate Server Action arguments exactly as HTTP input. Return serializable expected-error state or throw unexpected failures.
- Revalidate only affected paths/tags after successful mutation, or redirect after success. Do not invalidate before the write commits.

```ts
"use server";

import { revalidateTag } from "next/cache";
import { itemInputSchema } from "@/features/items/schema";
import { requireUser } from "@/server/auth";
import { createItem } from "@/server/items";

export async function createItemAction(input: unknown) {
  const user = await requireUser();
  const parsed = itemInputSchema.safeParse(input);
  if (!parsed.success) return { ok: false as const, issues: parsed.error.flatten() };

  const item = await createItem(user, parsed.data);
  revalidateTag("items");
  return { ok: true as const, id: item.id };
}
```

### SHOULD

- Use a discriminated result type for expected validation/conflict outcomes.
- Use `useActionState` where it improves progressive form feedback, subject to installed React/Next APIs.
- Keep Route Handlers thin and test their HTTP contract separately from use cases.

### AVOID

- Creating an internal Route Handler solely so a Server Component can call the same application over HTTP. Call the server service directly.
- Trusting hidden form fields for ownership, price, role, or permission.
- Broad `catch` blocks that convert framework control-flow errors to 500 responses.
- Returning raw ORM entities, Axios responses, stack traces, or provider errors.

## 10. Services and Server Data Fetching

### MUST

- Put transport mechanics and server data access outside components. Return validated contracts or domain/view models, not raw response wrappers.
- Use the native server `fetch` integration when its memoization/cache semantics are useful; otherwise make cache behavior explicit.
- Specify freshness intentionally with the installed APIs: uncached/request-time data, timed revalidation, or tag/path invalidation. Defaults have changed between Next.js versions.
- Include identity/tenant/permission scope in any server cache key. Never share personalized data through a public cache.
- Apply timeouts/abort signals, normalize known errors, and avoid unbounded retries.
- Read request-scoped cookies and headers inside request execution, not during module evaluation.

```ts
import "server-only";

export async function getCatalog(): Promise<CatalogItem[]> {
  const response = await fetch(`${serverEnv.API_URL}/catalog`, {
    next: { revalidate: 300, tags: ["catalog"] },
    signal: AbortSignal.timeout(8_000),
  });

  if (!response.ok) throw new UpstreamError(response.status);
  return catalogSchema.parse(await response.json());
}
```

### SHOULD

- Fetch independent resources in parallel and dependent resources sequentially.
- Deduplicate repeated non-`fetch` server work with the supported request memoization primitive.
- Define explicit data transfer objects between persistence, transport, and UI when their shapes differ.

### AVOID

- Accidental waterfalls, fetching entire records when only a summary is rendered, or setting every request to uncached.
- Caching access tokens, cookies, or mutable personalized responses globally.
- Calling a browser-oriented Axios singleton from a Server Component when direct server access is available.

## 11. React Query and Client Server-State

Use React Query for client-owned asynchronous server state: polling, optimistic mutations, user-triggered refetching, and long-lived interactive screens. Do not duplicate data already owned effectively by a Server Component without a UX reason.

### MUST

- Create one stable `QueryClient` per browser session/provider lifecycle, not during each render.
- Use semantic key factories and include every input that changes the result.
- Keep query functions in feature/service modules and return normalized data.
- Set `staleTime`, garbage collection, retry, and refetch behavior deliberately.
- Invalidate or update the narrowest relevant keys after mutation.
- Cancel conflicting requests and provide rollback context for optimistic updates.

```ts
export const itemKeys = {
  all: ["items"] as const,
  lists: () => [...itemKeys.all, "list"] as const,
  list: (filters: ItemFilters) => [...itemKeys.lists(), filters] as const,
  details: () => [...itemKeys.all, "detail"] as const,
  detail: (id: string) => [...itemKeys.details(), id] as const,
};
```

### SHOULD

- Normalize filter objects so equivalent URLs create equivalent keys.
- Prefetch/dehydrate on the server only when it measurably improves first render and the hydration boundary is correctly scoped.
- Distinguish initial pending state from background fetching and stale content.

### AVOID

- Anonymous keys such as `[page, limit]`, functions/nonserializable values in keys, and blanket cache invalidation.
- Duplicating React Query data into a global store.
- Creating query hooks that hide required parameters or authorization context.
- Copying server cache durations into client `staleTime` without considering UX.

## 12. State Ownership

Use one owner for each state:

1. **Server state:** Server Components/cache or React Query.
2. **URL state:** shareable filters, pagination, sort, search, and navigable selection.
3. **Global client state:** small cross-route UI state or client-only workflow state.
4. **Local state:** ephemeral interaction inside the nearest component.
5. **Derived state:** compute during render or in a selector.

### MUST

- Keep server data out of Jotai/Redux-like stores unless offline/client workflow requirements genuinely require a synchronized copy.
- Scope global atoms/stores to avoid user data surviving logout or tenant changes.
- Derive values instead of synchronizing duplicates with effects.

### SHOULD

- Use component state first; promote state only when multiple distant owners need it.
- Put a stateful provider as low as practical.

### AVOID

- A global store for every dialog, input, and fetched response.
- Storing React elements, router instances, request objects, or server credentials in global state.
- Effects that continuously copy props, URL state, query data, and form data into each other.

## 13. Forms with React Hook Form and Zod

### MUST

- Make the Zod schema the runtime source of truth and infer the input type. Keep output types distinct when transforms/coercion change shape.
- Configure `zodResolver`, explicit defaults, correct controlled/uncontrolled behavior, and field names that match the schema.
- Validate again on the trusted server boundary; client validation is UX, not security.
- Map server field errors to fields and cross-cutting failures to a form-level message.
- Disable or guard duplicate submission while pending, while preserving accessible status feedback.
- Build a new payload instead of mutating form values.
- Validate file count, size, type, and content server-side; browser MIME/type checks are insufficient.

```tsx
const schema = z.object({
  name: z.string().trim().min(1, "Enter a name"),
  email: z.string().trim().email("Enter a valid email address"),
});

type FormInput = z.input<typeof schema>;

const form = useForm<FormInput>({
  resolver: zodResolver(schema),
  defaultValues: { name: "", email: "" },
});
```

### SHOULD

- Use native input types, autocomplete tokens, and browser semantics.
- Focus the first invalid field, keep entered values after recoverable errors, and announce result status.
- Use schema preprocessing only for intentional HTML serialization differences such as empty strings or numeric inputs.

### AVOID

- `valueAsNumber` without handling `NaN`, all-optional update schemas without business rules, or schema/type duplication.
- Resetting a form on failed submission.
- Using placeholders as labels or disabling submit merely because untouched fields are empty when validation can explain the issue.

## 14. Component Taxonomy, Dialogs, and Tables

### Component taxonomy

- **UI primitives** are accessible, domain-free controls and visual foundations.
- **Common components** compose primitives into reusable application patterns.
- **Feature components** own domain language, workflows, and feature-specific queries/forms.
- **Route components** connect URL/server data to feature composition.

### MUST

- Preserve this dependency direction and avoid placing business workflows in primitive files.
- Use named exports for reusable components; retain required default exports for framework route files.
- Keep one clear responsibility per component; split by ownership/data flow, not arbitrary line count.

### Dialogs

- Use an established accessible dialog primitive with focus trap, labelled title, optional description, Escape handling, focus restoration, and inert background behavior.
- Use an alert dialog for destructive confirmation and state the specific consequence.
- Keep dialog open on recoverable mutation failure; show the error and prevent duplicate submission.
- For URL-addressable detail/create flows, prefer a real route, optionally presented through intercepting routes.
- Avoid nested dialogs, click-only backdrop dismissal for destructive work, and rendering a separate heavy dialog instance in every table row.

### Tables

- Use semantic `<table>`, `<caption>`, `<thead>`, `<th scope>`, and cells for tabular data. Use a list/grid when the content is not tabular.
- Put pagination, filtering, and sorting on the server/URL for large datasets; send explicit sort/filter contracts.
- Provide loading skeletons, empty state, error state, and horizontal overflow or an intentional small-screen alternative.
- Label row action menus with row context and make selection state accessible.
- Use stable row identifiers; never use array indexes for mutable data.
- Avoid loading the full dataset for client pagination, ambiguous icon-only actions, and hiding essential columns without another way to access them.

## 15. Styling, Motion, and Responsiveness

### MUST

- Follow the existing styling system, tokens, class-merging utility, and component variants.
- Build mobile-first and test narrow, medium, and wide layouts with realistic long content and zoom.
- Reserve space for asynchronous media/content and prevent unintended horizontal overflow.
- Respect `prefers-reduced-motion`; motion must not be required to understand or operate the UI.
- Animate compositor-friendly `transform` and `opacity` where practical. Keep interaction feedback short and interruptible.
- Use logical properties where directionality may change and account for safe areas in edge-to-edge mobile UI.

### SHOULD

- Prefer CSS/container queries over JavaScript viewport checks for presentation.
- Use design tokens for color, spacing, typography, radius, and elevation.
- Dynamically import genuinely heavy visualization/editor/map modules and provide a stable fallback.

### AVOID

- Arbitrary one-off colors/spacing, excessive `z-index`, layout animation of large regions, and `transition: all`.
- Rendering materially different server/client markup based on `window.innerWidth`.
- Hover-only disclosure, fixed heights around variable text, and truncation that hides essential information.

## 16. Accessibility

### MUST

- Use semantic HTML and native controls before ARIA. Every interactive element must be keyboard operable and visibly focusable.
- Provide one descriptive page `<h1>`, logical heading order, meaningful link/button names, form labels, instructions, and associated errors.
- Maintain focus through navigation, dialogs, async replacement, and errors. Use a skip link for repeated navigation when appropriate.
- Announce asynchronous form/status changes with an appropriately scoped live region; do not announce every background refresh.
- Meet the applicable contrast target and preserve usability at 200% zoom and text enlargement.
- Give touch targets adequate size and spacing; do not rely on color alone.
- Respect reduced motion and avoid unexpected autoplay.

### SHOULD

- Test keyboard-only operation and at least one screen-reader path for changed critical workflows.
- Use route announcements or meaningful title updates for client navigation where framework defaults are insufficient.
- Keep DOM reading order aligned with visual order.

### AVOID

- Positive `tabIndex`, clickable `<div>` elements, redundant ARIA, focus removal without replacement, and `aria-hidden` on focusable descendants.
- Placeholder-only labels and generic names such as “Click here” or repeated unlabeled “Edit” buttons.

## 17. Testing

### MUST

- Test changed behavior at the narrowest useful level and add integration coverage for important boundaries.
- For Server Components, test extracted server functions/use cases and rendered outcomes with tooling that supports the installed version.
- Test Client Components with user-visible role/label queries and realistic user events.
- Cover relevant loading, empty, success, error, not-found, authorization, validation, and retry states.
- Test Route Handlers as HTTP contracts and Server Actions as untrusted mutation boundaries.
- Test query key/invalidation behavior, optimistic rollback, URL serialization, and form payload/error mapping when changed.
- Mock network, time, browser APIs, and providers at boundaries; never call live services.

### SHOULD

- Use Vitest/Jest and React Testing Library for units/components, Mock Service Worker or equivalent for HTTP boundaries, and Playwright for critical navigation/auth flows.
- Include accessibility assertions and keyboard interaction in component/end-to-end tests.
- Use deterministic factories and fixed time zones for date behavior.

### AVOID

- Snapshot-only coverage, “renders without crashing” as the only assertion, implementation selectors, and mocking the unit under test.
- Tests that depend on execution order, real clocks, production credentials, or generated build output.

## 18. Nx, Packages, Build, Docker, PWA, and Observability

Apply this section only when the capability exists or the task introduces it.

### Nx and workspace packages

#### MUST

- Run targets through the workspace's declared commands and project names; inspect the project graph before changing task dependencies.
- Declare cacheable target inputs/outputs accurately. Do not cache long-running development servers or tasks with undeclared external side effects.
- Keep package peer/runtime dependencies and exports correct; do not rely on accidental root hoisting.

#### SHOULD

- Use affected targets in CI for large monorepos and focused project targets during development.
- Keep shared TypeScript/lint configuration versioned in dedicated packages when already established.

#### AVOID

- Running workspace-wide formatting to change one app, circular package dependencies, and importing application source through relative paths from packages.

### Production build and Docker

#### MUST

- Treat `next build` as required verification for framework/configuration changes.
- For `output: "standalone"`, copy the standalone server, static assets, and public assets using paths that match monorepo output.
- Use a lockfile-frozen install, multi-stage build, non-root runtime user, production environment, and a minimal runtime image.
- Provide only required build arguments. Secrets MUST use secret mounts/runtime injection and MUST NOT be copied into layers or exposed through `NEXT_PUBLIC_*`.
- Add a narrow `.dockerignore`; never send local environment files, VCS data, caches, or development artifacts as build context.

#### SHOULD

- Pin a supported Node major consistently across local, CI, and container environments.
- Add a health endpoint/check that tests application readiness without exposing internals.
- Set telemetry policy explicitly and handle graceful shutdown where custom runtime work requires it.

#### AVOID

- Global package-manager installs without version pinning, running as root, copying the entire source into the final image, and assuming root-level `.next` paths in a monorepo.

### PWA and service workers

#### MUST

- Add PWA behavior only for a real offline/installability requirement.
- Version caches and define update behavior. Never cache authenticated HTML, session endpoints, mutation responses, or sensitive API data with broad strategies.
- Ensure service workers are disabled or predictable in development/tests and verify unregister/update migration behavior.
- Keep manifest identity, icons, scope, start URL, display, and theme colors valid.

#### SHOULD

- Prefer network-first for changing documents/data and cache-first only for immutable revisioned assets.
- Provide offline and update UX, and test a deployed production build because development mode is not representative.

#### AVOID

- Aggressive navigation caching by default, committing generated service-worker bundles unless the tool requires tracked artifacts, and assuming “online again” makes queued mutations safe.

### Observability

#### MUST

- Initialize instrumentation through supported server/client/edge entry points for the installed version.
- Capture unexpected errors with environment, release, route/operation, and safe correlation identifiers.
- Redact authorization headers, cookies, tokens, passwords, form contents, and unnecessary personal data from logs, traces, replay, and breadcrumbs.
- Upload source maps securely during CI/build and prevent public source-map exposure when not intended.
- Avoid duplicate initialization and duplicate error reporting across boundaries.

#### SHOULD

- Use structured logs and distributed trace context across upstream calls.
- Sample expensive traces/replays deliberately by environment and monitor web vitals relevant to user experience.

#### AVOID

- Importing server instrumentation into client code, embedding observability auth tokens in runtime bundles, and reporting expected validation failures as incidents.

## 19. Verification Workflow

The agent **MUST** use repository scripts and the package manager selected by the lockfile. Adapt this sequence to the actual workspace:

```bash
# Focused tests first
pnpm --filter web test -- --run path/to/changed.test.tsx

# Non-mutating quality checks
pnpm --filter web exec biome check src/path/to/changed.tsx
pnpm --filter web exec tsc --noEmit
pnpm --filter web test -- --run

# Framework integration and production behavior
pnpm --filter web build
# In Nx workspaces, use the declared target when appropriate:
pnpm exec nx run web:build
```

### MUST

1. Format only changed files using configured tooling.
2. Run non-mutating lint/check, type-checking, focused tests, then broader tests/build based on blast radius.
3. Inspect build output for dynamic-rendering bailouts, route conflicts, unsupported configuration, bundle regressions, and PWA/observability warnings.
4. Exercise changed routes at realistic viewport sizes and test keyboard behavior when UI changed.
5. Inspect the final diff for accidental client boundaries, secrets, debug output, generated files, unrelated formatting, and contract changes.
6. Report exact commands and results. Distinguish pre-existing failures from introduced failures with evidence.

### SHOULD

- Analyze client bundles when adding dependencies or moving a boundary client-side.
- Build and smoke-test the production container when Docker, output paths, runtime environment, or workspace packaging changes.
- Test a production deployment-like environment for middleware, image hosts, service workers, and instrumentation.

### AVOID

- Using auto-fix as final lint verification.
- Claiming success from development mode alone.
- Deleting caches or lockfiles to hide an unexplained failure.

## 20. Prohibited Anti-Patterns

The agent **MUST NOT**:

- Introduce Pages Router APIs (`getServerSideProps`, `getStaticProps`, `_app`, or `_document`) into App Router routes.
- Add `"use client"` to a page/layout or broad subtree merely for one hook or event.
- Leak secrets or privileged server modules into the client bundle, including through barrels or `NEXT_PUBLIC_*`.
- Trust client claims for identity, ownership, roles, prices, permissions, or mutation authorization.
- Assume middleware, route visibility, or UI controls provide authorization.
- Read cookies/headers once at module initialization or globally cache personalized data.
- Fetch this application's own Route Handler from a Server Component when a direct server function is available.
- Use unvalidated `params`, `searchParams`, form data, JSON, cookies, headers, environment variables, or upstream responses.
- Depend on undocumented caching defaults, indiscriminately call `revalidatePath("/")`, or invalidate all React Query keys after every mutation.
- Recreate `QueryClient` or global providers during render.
- Mirror server, URL, query, form, and local state through effects.
- Use array indexes as mutable row keys, render per-row dialog trees unnecessarily, or ship client-side pagination for unbounded datasets.
- Suppress hydration errors, type errors, lint rules, image optimization, or accessibility warnings instead of fixing the cause.
- Use broad remote image patterns, open redirects, unsafe HTML without sanitization, or raw user input in URLs/headers.
- Cache authenticated pages or sensitive API responses in a service worker.
- Log or report credentials, cookies, tokens, raw form data, or unnecessary personal information.
- Commit `.next`, Nx caches, test artifacts, generated service workers, source maps, or standalone output unless repository policy explicitly tracks them.
- Add an abstraction, provider, store, dependency, route handler, or workspace package without a demonstrated ownership or reuse need.
