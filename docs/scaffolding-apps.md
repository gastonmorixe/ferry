# Scaffolding Apps with `ferry new`

This guide covers creating a new app with Ferry's built-in generators, deciding whether to deploy immediately, and working with the generated project afterward.

## What `ferry new` Does

`ferry new` creates a starter app from a built-in template, writes it to disk, initializes a git repository, validates the generated project, and can optionally chain straight into `ferry deploy`.

That means Ferry supports three distinct flows:

```bash
# 1. Scaffold only
ferry new myapp -t express -y --no-deploy

# 2. Scaffold, then deploy immediately
ferry new myapp -t express --deploy -y

# 3. Scaffold interactively, then choose at the deploy prompt
ferry new myapp -t express
```

`ferry new` is a local filesystem operation. It does not require Docker, Dokku, or Cloudflare just to generate the app. Deployment is the point where Ferry checks the server-side prerequisites.

## Available Templates

List the built-in templates with:

```bash
ferry new --list
```

Current categories:

- Backend: `express`, `nestjs`, `fastapi`, `django`, `go-net`, `go-fiber`, `axum`, `actix`
- Frontend: `react`
- Fullstack: `nextjs`, `rails`

Each template has a default port and generates a Dockerfile-ready project that Ferry can deploy.

## Basic Usage

### Scaffold only

Use this when you want Ferry to generate the app now, but you want to deploy later.

```bash
ferry new myapp -t express -y --no-deploy
```

This creates the project and prints the next step:

```bash
ferry deploy myapp
```

### Scaffold and deploy in one command

Use this when you want a one-shot flow from template to running app.

```bash
ferry new myapp -t express --deploy -y
```

Ferry will:

1. Generate the app
2. Initialize git in the output directory
3. Validate the generated files
4. Call `ferry deploy myapp -d <output_dir>`

### Interactive flow

If you omit `--template`, Ferry shows the template picker in TTY mode:

```bash
ferry new myapp
```

The interactive flow is:

1. Enter the app name
2. Choose a category
3. Choose a framework
4. Review the generation plan
5. Confirm creation
6. Decide whether to deploy immediately

## Important Flags

### `--template`, `-t`

Selects the generator to use.

```bash
ferry new myapp -t fastapi
```

### `--deploy`

Immediately chains into `ferry deploy` after generation.

```bash
ferry new myapp -t nextjs --deploy -y
```

### `--no-deploy`

Prevents the post-generation deploy prompt and stops after scaffold creation.

```bash
ferry new myapp -t rails -y --no-deploy
```

### `--output`, `-o`

Writes the project to a custom directory instead of the default app storage location.

```bash
ferry new myapp -t react -o ~/projects/myapp -y
```

If you use a custom output directory, later deployment must include `--dir`:

```bash
ferry deploy myapp -d ~/projects/myapp
```

### `--port`, `-p`

Overrides the template's default port.

```bash
ferry new myapp -t express -p 9000 -y --no-deploy
```

This is useful when the generated app needs to match an expected internal port before deployment.

### `--list`, `-l`

Prints the available templates and exits.

```bash
ferry new --list
```

### `--yes`, `-y`

Runs non-interactively. With `-y`, both the app name and template are required.

```bash
ferry new myapp -t django -y
```

This fails:

```bash
ferry new -y -t django
ferry new myapp -y
```

Because Ferry cannot infer missing required values in non-interactive mode.

## Where Apps Are Created

By default, Ferry writes generated apps to:

```bash
$FERRY_APPS_DIR/<name>
```

If `FERRY_APPS_DIR` is not set, the default is:

```bash
<ferry-install-dir>/apps/<name>
```

This matters because `ferry deploy <name>` auto-detects repositories in that location. So this works with no extra flags:

```bash
ferry new myapp -t express -y --no-deploy
ferry deploy myapp
```

If you override the output location with `--output`, auto-detection does not apply unless the output directory matches `FERRY_APPS_DIR`.

## What Gets Generated

The generated project depends on the selected template, but Ferry consistently does the following:

- writes framework-specific source files
- writes a Dockerfile suitable for Dokku deployment
- writes `.gitignore` and `.dockerignore`
- copies Ferry's shared styling/assets where needed
- substitutes template placeholders such as app name, port, and Ferry version
- initializes a git repository
- creates an initial commit when local git identity is configured

If git is installed but `user.name` or `user.email` is missing, Ferry still creates the repository and stages the files, but it skips the initial commit with a warning.

## Deploying Later

If you chose scaffold-only, deploy later with one of these flows.

### Default app location

```bash
ferry new myapp -t express -y --no-deploy
ferry deploy myapp
```

### Custom app location

```bash
ferry new myapp -t express -o ~/projects/myapp -y --no-deploy
ferry deploy myapp -d ~/projects/myapp
```

### Deploy from the generated repo manually

You can also treat the generated app like any other local Ferry-managed repo:

```bash
cd apps/myapp
git remote add dokku ssh://dokku@localhost:3022/myapp
git push dokku main:master
```

## Common Workflows

### Start a backend app quickly

```bash
ferry new api -t fastapi --deploy -y
```

### Generate a frontend app but deploy later

```bash
ferry new ui -t react -y --no-deploy
ferry deploy ui
```

### Generate into a workspace outside Ferry

```bash
ferry new myapp -t nextjs -o ~/work/myapp -y --no-deploy
ferry deploy myapp -d ~/work/myapp
```

### Explore templates before choosing

```bash
ferry new --list
ferry new myapp
```

## Relationship to `ferry deploy`

`ferry new` creates source code. `ferry deploy` creates and configures the deployed app in Dokku and Cloudflare.

Use `ferry new` when you need Ferry to generate the application itself.

Use `ferry deploy` when:

- you already have a local app repository
- you want to deploy a GitHub repo directly
- you want infrastructure only
- you are redeploying or managing an existing app

For the deeper deployment lifecycle, see [Deploying Apps](deploying-apps.md).

## Troubleshooting

### `ferry new` says the template is required

That happens in non-interactive mode when `--template` is missing.

```bash
ferry new myapp -y
```

Fix:

```bash
ferry new myapp -t express -y
```

### `ferry new` says the output directory already exists

Ferry refuses to write into an existing directory.

Fix one of these:

- choose a different app name
- remove the existing directory yourself
- use `--output` with a different path

### `ferry deploy myapp` cannot find the generated app

That usually means you generated into a custom directory.

Fix:

```bash
ferry deploy myapp -d /path/to/generated/app
```

### Git repo exists but there was no initial commit

That means local git identity is missing.

Check:

```bash
git config --global user.name
git config --global user.email
```

Then commit manually inside the generated app:

```bash
cd apps/myapp
git add -A
git commit -m "Initial scaffold"
```
