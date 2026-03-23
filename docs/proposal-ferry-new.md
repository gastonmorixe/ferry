# Proposal: `ferry new` Command

**Date:** 2026-03-23T17:27:33-03:00
**Status:** Draft
**Ferry version:** 0.5.1

---

## Table of Contents

1. [Command Design](#1-command-design)
2. [App Storage Location](#2-app-storage-location)
3. [Template Architecture](#3-template-architecture)
4. [Generator Catalog](#4-generator-catalog)
5. [Template Reuse Matrix](#5-template-reuse-matrix)
6. [Directory Structure](#6-directory-structure)
7. [CLI Integration](#7-cli-integration)
8. [Mock Terminal Output](#8-mock-terminal-output)
9. [Implementation Notes](#9-implementation-notes)

---

## 1. Command Design

### Command Name: `ferry new`

Rationale for `new` over `create` or `init`:
- `create` conflicts conceptually with `deploy` (which "creates" the app in Dokku)
- `init` implies initializing in the current directory (like `git init`), but this command scaffolds into a new directory
- `new` is unambiguous: it generates something from scratch, separate from deployment

### Syntax

```
ferry new [<name>] [flags]
```

### Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--template <id>` | `-t` | Generator template ID (e.g. `express`, `nextjs`, `fastapi`) |
| `--output <dir>` | `-o` | Output directory (default: `$FERRY_APPS_DIR/<name>`) |
| `--port <port>` | `-p` | Override default port for the template |
| `--deploy` | | Chain into `ferry deploy` after generation |
| `--no-deploy` | | Skip deploy prompt (for scripting) |
| `--yes` | `-y` | Non-interactive mode (requires `--template` and `<name>`) |
| `--list` | `-l` | List all available templates and exit |

### Non-interactive Requirements

When `-y` is used, both `<name>` and `--template` are mandatory:

```bash
ferry new myapp -t express -y          # generate and done
ferry new myapp -t express --deploy -y # generate + deploy
```

### Behavior Flow

```
1. Resolve app name (arg or prompt)
2. Resolve template (flag or TUI selector)
3. Resolve output directory (flag or default)
4. Show summary, confirm
5. Run generator (copy template, substitute variables)
6. Initialize git repo
7. Show success + next steps
8. Optionally offer to deploy (prompt or --deploy flag)
```

---

## 2. App Storage Location

### Recommendation: Keep `$SCRIPT_DIR/apps/`

**Decision:** Generated apps go to `$SCRIPT_DIR/apps/<name>/` by default, overridable with `--output`.

**Reasoning:**

| Option | Pros | Cons |
|--------|------|------|
| `$SCRIPT_DIR/apps/` | Already in `.gitignore`. `cmd_deploy` auto-detects apps here. Zero config. Visible to user next to the tool. | Couples app storage to ferry install location. |
| `~/.local/share/ferry/apps/` | XDG-compliant. Clean separation. | Invisible. Requires extra `--dir` on every deploy. `cmd_deploy` auto-detection won't find apps there. |
| `~/.config/ferry/apps/` | Familiar config path. | XDG says config is for config, not data. Same discoverability problem. |
| Current working directory | User controls placement. | Loses integration with `ferry deploy` auto-detection. |

The strongest argument for `$SCRIPT_DIR/apps/` is that **`cmd_deploy` already auto-detects apps there** (line 1542-1546 of the ferry script):

```bash
elif [[ -d "$SCRIPT_DIR/apps/$name/.git" ]]; then
    app_dir="$SCRIPT_DIR/apps/$name"
    has_app_source=true
    info "Found existing app source at $app_dir"
```

This means `ferry new myapp -t express` followed by `ferry deploy myapp` Just Works with zero extra flags. That seamless chain is the killer feature.

The `--output` flag provides an escape hatch for users who want apps elsewhere. When used, the user must pass `--dir` to deploy:

```bash
ferry new myapp -t express -o ~/projects/myapp
ferry deploy myapp -d ~/projects/myapp
```

**Environment variable:** Introduce `FERRY_APPS_DIR` (defaults to `$SCRIPT_DIR/apps`) so power users can globally redirect app storage. This also lets `cmd_deploy` auto-detection respect the override.

---

## 3. Template Architecture

### The Core Problem

Every generated app must serve a "request info" page that shows:

**Server-side data** (SSR/backend frameworks):
- Client IP address
- Request method, URL, protocol
- All request headers (Host, User-Agent, Accept, etc.)
- Server hostname (container ID)
- Server timestamp
- Response time

**Client-side data** (SPAs like React/Vite):
- Page URL, query params
- `navigator.userAgent`
- Screen dimensions
- Note: "Cannot show server-side headers/IP from a static SPA"

### Three-Layer Template System

```
Layer 1: Shared Assets        (response schema, CSS, HTML layout)
Layer 2: Language Adapters     (how to collect request info in each language)
Layer 3: Generator Scaffolds   (full project structure per framework)
```

#### Layer 1: Shared Assets

These files are literally identical across all generators:

| Asset | Purpose | Used by |
|-------|---------|---------|
| `style.css` | Single CSS file for the HTML info page | All generators (embedded or copied) |
| `response-schema.json` | Canonical JSON shape for request info | All server-side generators |
| `.dockerignore` | Standard ignore file | All generators |
| `.gitignore` | Standard ignore file | All generators |

**`response-schema.json`** defines the canonical shape:

```json
{
  "app": "{{APP_NAME}}",
  "ferry": true,
  "timestamp": "2026-03-23T17:27:33Z",
  "server": {
    "hostname": "container-abc123",
    "port": 5000
  },
  "request": {
    "method": "GET",
    "url": "/",
    "protocol": "HTTP/1.1",
    "ip": "192.168.1.1",
    "headers": {
      "host": "myapp.example.com",
      "user-agent": "Mozilla/5.0...",
      "...": "..."
    }
  }
}
```

This schema is the contract. Every server-side generator must produce JSON in this shape at `GET /json`. The HTML, XML, and Markdown renderings are derived from this same data.

#### Layer 2: Language Adapters

Each language needs a function/snippet that collects request info into the schema above. These are small, isolated pieces:

| Language | Adapter | Notes |
|----------|---------|-------|
| JavaScript/TS | `collect-request-info.ts` | Works for Express, NestJS, Next.js API routes |
| Python | `collect_request_info.py` | Works for FastAPI and Django views |
| Ruby | `collect_request_info.rb` | Works for Rails controllers |
| Go | `collect_request_info.go` | Works for net/http and Fiber |
| Rust | `collect_request_info.rs` | Different for Axum vs Actix (extractor patterns differ) |

These are NOT shared as runtime code between generators. They are source snippets that get copied into the generated project. The point is that a human maintains one canonical "collect request info" implementation per language rather than duplicating logic across generators in the same language.

#### Layer 3: Generator Scaffolds

Each generator is a self-contained directory with:
- A `generate.sh` script (the entry point called by `ferry new`)
- Template files with `{{VARIABLE}}` placeholders
- A `Dockerfile.template`
- A `metadata.sh` file (name, description, default port, category)

### Response Formats

Every server-side app serves four endpoints:

| Endpoint | Content-Type | Description |
|----------|-------------|-------------|
| `GET /` | `text/html` | Styled HTML page showing request info |
| `GET /json` | `application/json` | Raw JSON per the schema |
| `GET /xml` | `application/xml` | XML rendering of the same data |
| `GET /text` | `text/plain` | Markdown-formatted plain text |
| `GET /health` | `text/plain` | Returns `ok` (for Dokku health checks) |

For **static SPAs** (React/Vite), the single `index.html` shows client-side info with a note that server headers are unavailable. There are no `/json`, `/xml`, `/text` endpoints since there is no server.

For **SSR frameworks** (Next.js, Nuxt, SvelteKit), the HTML page is server-rendered and includes full request info. The API endpoints (`/json`, `/xml`, `/text`) are implemented as API routes.

### HTML Template Design

A single HTML template (with CSS) is shared conceptually. It renders:

```
+--------------------------------------------------+
|  [Ferry Logo]  myapp                             |
|  Deployed with Ferry v0.5.1                      |
+--------------------------------------------------+
|                                                  |
|  Request Info                                    |
|  +-----------+--------------------------------+  |
|  | Method    | GET                            |  |
|  | URL       | /                              |  |
|  | Protocol  | HTTP/1.1                       |  |
|  | Client IP | 192.168.1.100                  |  |
|  +-----------+--------------------------------+  |
|                                                  |
|  Headers                                         |
|  +-----------+--------------------------------+  |
|  | Host      | myapp.example.com              |  |
|  | User-Agent| Mozilla/5.0...                 |  |
|  | Accept    | text/html,...                   |  |
|  +-----------+--------------------------------+  |
|                                                  |
|  Server                                          |
|  +-----------+--------------------------------+  |
|  | Hostname  | abc123def456                   |  |
|  | Port      | 5000                           |  |
|  | Time      | 2026-03-23T17:27:33Z           |  |
|  +-----------+--------------------------------+  |
|                                                  |
|  Formats: [HTML] [JSON] [XML] [Text]            |
|                                                  |
|  Ferry — https://github.com/gastonmorixe/ferry  |
+--------------------------------------------------+
```

The CSS for this layout lives in `generators/_shared/assets/style.css`. Each server-side generator embeds or references it. The HTML structure is in `generators/_shared/assets/page.html` as a reference, but each framework renders it natively (EJS for Express, JSX for React/Next, Jinja for Python, etc.).

---

## 4. Generator Catalog

### Tier 1: Must-Have (ship with v1)

| ID | Framework | Language | Type | Default Port | Category |
|----|-----------|----------|------|-------------|----------|
| `express` | Express | TypeScript | Backend/API | 5000 | backend |
| `nextjs` | Next.js | TypeScript | SSR | 3000 | fullstack |
| `react` | React (Vite) | TypeScript | SPA/Static | 4173 (preview) | frontend |
| `nestjs` | NestJS | TypeScript | Backend/API | 3000 | backend |
| `fastapi` | FastAPI | Python | Backend/API | 8000 | backend |
| `django` | Django | Python | Backend/API | 8000 | backend |
| `rails` | Rails | Ruby | Fullstack | 3000 | fullstack |
| `go-net` | net/http | Go | Backend/API | 8080 | backend |
| `go-fiber` | Fiber | Go | Backend/API | 3000 | backend |
| `axum` | Axum | Rust | Backend/API | 3000 | backend |
| `actix` | Actix-web | Rust | Backend/API | 8080 | backend |

### Tier 2: Nice-to-Have (add later)

| ID | Framework | Language | Type | Default Port |
|----|-----------|----------|------|-------------|
| `nuxt` | Nuxt 3 | TypeScript | SSR | 3000 |
| `sveltekit` | SvelteKit | TypeScript | SSR | 3000 |
| `astro` | Astro | TypeScript | SSR/Static | 4321 |
| `remix` | Remix | TypeScript | SSR | 3000 |
| `flask` | Flask | Python | Backend/API | 5000 |
| `laravel` | Laravel | PHP | Fullstack | 8000 |

### Per-Generator: What Gets Generated

**Example: `express` generator output:**

```
myapp/
  app.ts
  package.json
  tsconfig.json
  Dockerfile
  .dockerignore
  .gitignore
```

**Example: `fastapi` generator output:**

```
myapp/
  main.py
  requirements.txt
  Dockerfile
  .dockerignore
  .gitignore
```

**Example: `react` generator output:**

```
myapp/
  index.html
  src/
    main.tsx
    App.tsx
    App.css
  package.json
  tsconfig.json
  vite.config.ts
  Dockerfile
  .dockerignore
  .gitignore
```

Every generated project is minimal: the fewest files needed to build, run, and deploy.

---

## 5. Template Reuse Matrix

### What Can Be Shared

| Asset | express | nestjs | nextjs | react | fastapi | django | rails | go-net | go-fiber | axum | actix |
|-------|---------|--------|--------|-------|---------|--------|-------|--------|----------|------|-------|
| `style.css` | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| `response-schema.json` | Yes | Yes | Yes | -- | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| `.dockerignore` | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| JS/TS request collector | Yes | Yes* | Yes* | -- | -- | -- | -- | -- | -- | -- | -- |
| Python request collector | -- | -- | -- | -- | Yes | Yes* | -- | -- | -- | -- | -- |
| Ruby request collector | -- | -- | -- | -- | -- | -- | Yes | -- | -- | -- | -- |
| Go request collector | -- | -- | -- | -- | -- | -- | -- | Yes | Yes* | -- | -- |
| Rust request collector | -- | -- | -- | -- | -- | -- | -- | -- | -- | Yes | Yes |
| Dockerfile | Own | Own | Own | Own | Own | Own | Own | Own | Own | Own | Own |
| Project structure | Own | Own | Own | Own | Own | Own | Own | Own | Own | Own | Own |

`*` = adapter is reused but requires framework-specific wrapping.

`--` = not applicable.

### Key Insight: What CANNOT Be Shared

1. **Dockerfiles** are always generator-specific. A Python Dockerfile (pip install) is fundamentally different from a Go Dockerfile (multi-stage build with compile step) or a Node Dockerfile (npm ci).

2. **Project structure** is always generator-specific. NestJS has modules/controllers/services. Django has settings/urls/views. Rails has its entire convention.

3. **HTML rendering** uses each framework's native approach:
   - Express: template literal or EJS
   - Next.js: JSX (React component)
   - React: JSX (client-side)
   - FastAPI: Jinja2 template or f-string
   - Django: Django template
   - Rails: ERB template
   - Go: `html/template`
   - Rust: `askama` or format string

4. **Request info collection** differs by language but can be shared within a language family, with caveats:
   - Express and NestJS both use `req.headers`, `req.ip`, etc. But NestJS wraps it in a decorator/controller pattern.
   - FastAPI and Django both use Python, but FastAPI uses `Request` from Starlette while Django uses `HttpRequest`.
   - Go net/http and Fiber have completely different request objects (`*http.Request` vs `*fiber.Ctx`).
   - Axum and Actix have different extractor patterns.

### Practical Sharing Strategy

Rather than a complex shared-library system, use a simpler approach:

1. **Shared assets** (`style.css`, `.dockerignore`, `.gitignore`, `response-schema.json`) are copied verbatim by every generator.
2. **Language adapters** are reference implementations that generator authors copy and adapt. They live in `generators/_shared/adapters/` as documentation/reference, not as runtime imports.
3. **Each generator is self-contained.** The `generate.sh` copies shared assets from `_shared/` and copies its own templates, performing variable substitution.

This avoids a fragile abstraction where changing a shared file breaks 11 generators. Each generator can diverge when needed.

---

## 6. Directory Structure

```
ferry/
  generators/
    _shared/
      assets/
        style.css                  # CSS for the HTML info page
        ferry-logo.svg             # Small SVG logo for the page
      schema/
        response-schema.json       # Canonical JSON response shape
      templates/
        dockerignore.template      # Common .dockerignore
        gitignore-node.template    # .gitignore for Node projects
        gitignore-python.template  # .gitignore for Python projects
        gitignore-go.template      # .gitignore for Go projects
        gitignore-rust.template    # .gitignore for Rust projects
        gitignore-ruby.template    # .gitignore for Ruby projects
      adapters/
        collect-request-info.ts    # Reference: JS/TS request info collector
        collect_request_info.py    # Reference: Python request info collector
        collect_request_info.rb    # Reference: Ruby request info collector
        collect_request_info.go    # Reference: Go request info collector
        collect_request_info.rs    # Reference: Rust request info collector
      helpers.sh                   # Shared bash functions for generators
    express/
      metadata.sh                  # name, description, port, category
      generate.sh                  # Entry point: scaffold the project
      templates/
        app.ts.template
        package.json.template
        tsconfig.json.template
        Dockerfile.template
    nestjs/
      metadata.sh
      generate.sh
      templates/
        src/
          main.ts.template
          app.module.ts.template
          app.controller.ts.template
          app.service.ts.template
        package.json.template
        tsconfig.json.template
        nest-cli.json.template
        Dockerfile.template
    nextjs/
      metadata.sh
      generate.sh
      templates/
        src/
          app/
            page.tsx.template
            layout.tsx.template
            globals.css.template
          app/api/
            info/route.ts.template
        package.json.template
        tsconfig.json.template
        next.config.ts.template
        Dockerfile.template
    react/
      metadata.sh
      generate.sh
      templates/
        index.html.template
        src/
          main.tsx.template
          App.tsx.template
          App.css.template
        package.json.template
        tsconfig.json.template
        vite.config.ts.template
        Dockerfile.template
    fastapi/
      metadata.sh
      generate.sh
      templates/
        main.py.template
        requirements.txt.template
        Dockerfile.template
    django/
      metadata.sh
      generate.sh
      templates/
        manage.py.template
        project/
          settings.py.template
          urls.py.template
          views.py.template
          wsgi.py.template
        requirements.txt.template
        Dockerfile.template
    rails/
      metadata.sh
      generate.sh
      templates/
        ... (minimal Rails structure)
        Dockerfile.template
    go-net/
      metadata.sh
      generate.sh
      templates/
        main.go.template
        go.mod.template
        Dockerfile.template
    go-fiber/
      metadata.sh
      generate.sh
      templates/
        main.go.template
        go.mod.template
        Dockerfile.template
    axum/
      metadata.sh
      generate.sh
      templates/
        src/
          main.rs.template
        Cargo.toml.template
        Dockerfile.template
    actix/
      metadata.sh
      generate.sh
      templates/
        src/
          main.rs.template
        Cargo.toml.template
        Dockerfile.template
```

### metadata.sh Format

```bash
# generators/express/metadata.sh
GENERATOR_ID="express"
GENERATOR_NAME="Express"
GENERATOR_DESC="TypeScript Express API server"
GENERATOR_LANG="TypeScript"
GENERATOR_CATEGORY="backend"    # backend | frontend | fullstack
GENERATOR_PORT=5000
GENERATOR_TYPE="server"         # server | static
```

### generate.sh Contract

Every `generate.sh` receives these environment variables:

```bash
APP_NAME="myapp"              # Validated app name
APP_PORT=5000                 # Port (from metadata default or --port override)
OUTPUT_DIR="/path/to/myapp"   # Target directory (already created, empty)
SHARED_DIR="/path/to/generators/_shared"  # Shared assets directory
FERRY_VERSION="0.5.1"         # For branding in generated pages
```

And must:
1. Copy and process its templates into `$OUTPUT_DIR`
2. Copy relevant shared assets from `$SHARED_DIR`
3. Perform `{{VARIABLE}}` substitution on all `.template` files
4. Exit 0 on success, non-zero on failure
5. NOT initialize git (the caller does that)
6. NOT install dependencies (keeps generation fast)

### helpers.sh: Shared Generator Utilities

```bash
# Called by generate.sh scripts
# Provides:
#   template_copy <src> <dest>       - copy and strip .template extension
#   template_sub <file>              - substitute {{VAR}} placeholders in-place
#   shared_copy <asset> <dest>       - copy from _shared/assets/
#   shared_gitignore <type> <dest>   - copy language-specific .gitignore
```

---

## 7. CLI Integration

### Changes to main()

Add `new` to the case statement in `main()` (line 2531):

```bash
case "$command" in
    new)     cmd_new "${args[@]+"${args[@]}"}" ;;   # NEW
    login)   cmd_login "${args[@]+"${args[@]}"}" ;;
    deploy)  cmd_deploy "${args[@]+"${args[@]}"}" ;;
    ...
```

### Changes to interactive_menu()

Insert "New" as the third option (before Deploy):

```bash
tui_select "Ferry" \
    "Status       System dashboard" \
    "List         Quick app list" \
    "New          Create app from template" \       # NEW
    "Deploy       Deploy a new app" \
    "Remove       Remove an app" \
    ...
```

### Changes to cmd_help()

Add under Usage:

```
ferry new [<name>] [-t <tmpl>] [-y]   Create app from template
```

Add a new section:

```
New Flags
  -t, --template    Generator template (express, nextjs, fastapi, etc.)
  -o, --output      Output directory (default: apps/<name>)
  -p, --port        Override default port
  --deploy          Deploy immediately after generation
  --no-deploy       Skip deploy prompt
  -l, --list        List available templates
  -y, --yes         Skip all confirmations (requires -t and <name>)
```

### cmd_new() Function Structure

```bash
cmd_new() {
    # NOTE: does NOT call preflight — generating an app doesn't need Docker/Dokku

    local name="" template="" output_dir="" port="" do_deploy="" list_mode=false

    # Parse arguments (same pattern as cmd_deploy)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--template)  template="$2"; shift 2 ;;
            -o|--output)    output_dir="$2"; shift 2 ;;
            -p|--port)      port="$2"; shift 2 ;;
            --deploy)       do_deploy=true; shift ;;
            --no-deploy)    do_deploy=false; shift ;;
            -l|--list)      list_mode=true; shift ;;
            -y|--yes)       YES=true; shift ;;
            -*)             error "Unknown flag: $1"; return 1 ;;
            *)              name="$1"; shift ;;
        esac
    done

    # --list mode: print templates and exit
    if $list_mode; then
        cmd_new_list
        return 0
    fi

    # Validate -y requirements
    if $YES && { [[ -z "$name" ]] || [[ -z "$template" ]]; }; then
        error "Both <name> and --template are required with -y/--yes."
        return 1
    fi

    section_header "New Application"
    echo ""

    # 1. App name
    # 2. Template selection (TUI or flag)
    # 3. Resolve output dir
    # 4. Summary + confirm
    # 5. Run generator
    # 6. Git init
    # 7. Success message
    # 8. Optional deploy chain
}
```

### Template Selection TUI

When no `--template` flag is given, present a two-level selection:

**Step 1: Choose category**

```
tui_select "Choose a category" \
    "Backend      API and server frameworks" \
    "Frontend     Client-side applications" \
    "Fullstack    SSR and full-stack frameworks"
```

**Step 2: Choose framework** (filtered by category)

For "Backend":
```
tui_select "Choose a backend framework" \
    "express      TypeScript Express API" \
    "nestjs       TypeScript NestJS (enterprise)" \
    "fastapi      Python FastAPI" \
    "django       Python Django" \
    "go-net       Go standard library (net/http)" \
    "go-fiber     Go Fiber" \
    "axum         Rust Axum" \
    "actix        Rust Actix-web"
```

For "Frontend":
```
tui_select "Choose a frontend framework" \
    "react        React (Vite + TypeScript)"
```

For "Fullstack":
```
tui_select "Choose a fullstack framework" \
    "nextjs       Next.js (React SSR)" \
    "rails        Ruby on Rails"
```

This two-step approach avoids overwhelming the user with 11+ options in a single list, while the `--template` flag bypasses it entirely.

### Deploy Chain

After successful generation:

```bash
if [[ -z "$do_deploy" ]] && ! $YES; then
    # Interactive: ask
    echo ""
    if confirm "Deploy '$name' now?"; then
        cmd_deploy "$name" -d "$output_dir"
    else
        # Show manual deploy instructions
    fi
elif [[ "$do_deploy" == "true" ]]; then
    cmd_deploy "$name" -d "$output_dir" ${YES:+"-y"}
fi
```

Key: `cmd_new` does NOT call `preflight`. It does not need Docker or Dokku running. If the user opts to deploy, `cmd_deploy` handles its own preflight.

---

## 8. Mock Terminal Output

### Interactive Mode

```
  ferry v0.5.1
  2026-03-23 17:27 -0300  ·  /home/pi/ferry

  New Application ──────────────────────────────────────────────────

  App name (a-z, 0-9, hyphens) > myapp

  Choose a category ────────────────────────────────────────────────

  > Backend      API and server frameworks
    Frontend     Client-side applications
    Fullstack    SSR and full-stack frameworks

  Choose a backend framework ───────────────────────────────────────

    express      TypeScript Express API
  > fastapi      Python FastAPI
    django       Python Django
    go-net       Go standard library (net/http)
    go-fiber     Go Fiber
    axum         Rust Axum
    actix        Rust Actix-web
    nestjs       TypeScript NestJS (enterprise)

  New App Plan ─────────────────────────────────────────────────────

    App name          myapp
    Template          fastapi (Python FastAPI)
    Output            /home/pi/ferry/apps/myapp
    Port              8000
    Endpoints         / (HTML) /json /xml /text /health

  Proceed? [y/N] > y

  [1/3] Generating project from fastapi template...
  . Copied 4 files
  . Applied template variables
  [2/3] Initializing git repository...
  . Created initial commit
  [3/3] Validating...
  . Dockerfile present
  . requirements.txt present
  . Port 8000 detected

  +----------------------------------+
  | App 'myapp' created successfully |
  +----------------------------------+

  Files:
    /home/pi/ferry/apps/myapp/main.py
    /home/pi/ferry/apps/myapp/requirements.txt
    /home/pi/ferry/apps/myapp/Dockerfile
    /home/pi/ferry/apps/myapp/.dockerignore
    /home/pi/ferry/apps/myapp/.gitignore

  Deploy 'myapp' now? [y/N] > n

  Next steps:

    $ cd /home/pi/ferry/apps/myapp
    $ ferry deploy myapp
```

### Non-Interactive Mode

```
  ferry v0.5.1
  2026-03-23 17:27 -0300  ·  /home/pi/ferry

  New Application ──────────────────────────────────────────────────

  [1/3] Generating project from express template...
  . Copied 5 files
  . Applied template variables
  [2/3] Initializing git repository...
  . Created initial commit
  [3/3] Validating...
  . Dockerfile present
  . package.json present
  . Port 5000 detected

  +----------------------------------+
  | App 'myapi' created successfully |
  +----------------------------------+

    Output: /home/pi/ferry/apps/myapi

  Deploy: ferry deploy myapi
```

### List Mode

```
$ ferry new --list

  ferry v0.5.1
  2026-03-23 17:27 -0300  ·  /home/pi/ferry

  Available Templates ──────────────────────────────────────────────

  Backend
    express      TypeScript Express API                    :5000
    nestjs       TypeScript NestJS (enterprise)            :3000
    fastapi      Python FastAPI                            :8000
    django       Python Django                             :8000
    go-net       Go standard library (net/http)            :8080
    go-fiber     Go Fiber                                  :3000
    axum         Rust Axum                                 :3000
    actix        Rust Actix-web                            :8080

  Frontend
    react        React (Vite + TypeScript)                 :4173

  Fullstack
    nextjs       Next.js (React SSR)                       :3000
    rails        Ruby on Rails                             :3000

  Usage: ferry new <name> -t <template>
```

---

## 9. Implementation Notes

### Variable Substitution

Templates use `{{VARIABLE}}` placeholders. The substitution is done by `sed` in `helpers.sh`:

```bash
template_sub() {
    local file="$1"
    sed -i \
        -e "s|{{APP_NAME}}|${APP_NAME}|g" \
        -e "s|{{APP_PORT}}|${APP_PORT}|g" \
        -e "s|{{FERRY_VERSION}}|${FERRY_VERSION}|g" \
        -e "s|{{YEAR}}|$(date +%Y)|g" \
        "$file"
}
```

### Git Initialization

After generation, `cmd_new` initializes a git repo:

```bash
git -C "$output_dir" init
git -C "$output_dir" add -A
git -C "$output_dir" commit -m "Initial scaffold from ferry new (${template})"
```

This is necessary because `cmd_deploy` and `dokku_push` require a git repo. The generated app is immediately deployable.

### No preflight

`cmd_new` deliberately skips `preflight()`. Generating an app is a local filesystem operation that does not require Docker, Dokku, or Cloudflare. This means a user can run `ferry new` on any machine, even without the full ferry infrastructure, then transfer the generated app to the deployment server.

### Generator Discovery

Rather than hardcoding the generator list, `cmd_new` discovers generators dynamically by scanning `$SCRIPT_DIR/generators/*/metadata.sh`. This makes adding new generators trivial: drop a directory with `metadata.sh` and `generate.sh`, and it appears in the menu.

```bash
discover_generators() {
    local gen_dir="$SCRIPT_DIR/generators"
    local -a generators=()
    for meta in "$gen_dir"/*/metadata.sh; do
        [[ -f "$meta" ]] || continue
        [[ "$(dirname "$meta")" == *"_shared"* ]] && continue
        generators+=("$meta")
    done
    echo "${generators[@]}"
}
```

### Validation Step

After generation, validate that critical files exist:

```bash
# Check Dockerfile exists
[[ -f "$output_dir/Dockerfile" ]] && success "Dockerfile present" || warn "No Dockerfile"

# Run detect_app_port on the generated project
local detect_result
detect_result=$(detect_app_port "$output_dir") || true
if [[ -n "$detect_result" ]]; then
    success "Port ${detect_result%% *} detected (${detect_result#* })"
fi
```

This reuses the existing `detect_app_port` function, confirming that `cmd_deploy` will be able to auto-detect the port later.

### Edge Cases

1. **Name collision:** If `$output_dir` already exists, error out. Do not overwrite.
2. **Missing generator:** If `--template` specifies an unknown ID, list available templates and exit.
3. **No git:** If `git` is not installed, warn but still generate (skip git init).
4. **Disk full:** Let filesystem errors propagate naturally; the generator will fail and report.

### Future Considerations

- **`ferry new --from <url>`**: Scaffold from a remote template repository (like `degit`).
- **`ferry new --blank`**: Scaffold a bare Dockerfile-only project with no framework.
- **Custom user templates:** Allow `~/.config/ferry/generators/` for user-defined generators that appear alongside built-in ones.
- **Post-generate hooks:** A `post-generate.sh` in the generator directory for framework-specific setup (e.g., running `npx prisma init`).
