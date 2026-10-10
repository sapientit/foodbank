# Bootstrap: setting up a development machine

Step-by-step instructions for an AI agent to build the full local development environment from
nothing, starting from a clone of this repository. Carry the steps out in order. Each ends with a
check; do not move on until it passes. If one fails, stop and report the failure and its output
rather than working around it.

**This sets up local development, then checks the machine can push and deploy.** Setting up needs no
Cloudflare credentials and touches no deployed system. The credentials for releasing (the charity's
Cloudflare token, the Resend key) are put in place by a person — see "Once, when the machine is set
up" in [`deploying.md`](./deploying.md). Step 7 checks they work, through `./check-setup`, which
reads them itself and never shows them. **Never ask for, read or store a credential while
bootstrapping.**

## 1. Prerequisites

| Tool    | Version                      | Check            |
| ------- | ---------------------------- | ---------------- |
| git     | any current                  | `git --version`  |
| Node.js | **26 or newer** (both repos) | `node --version` |
| npm     | comes with Node              | `npm --version`  |

**This runs on macOS or Windows.** Linux is not supported.

**On Windows, everything here runs in Git Bash**, which comes with Git for Windows: every command in
this file, and `./push`, `./deploy` and `./check-setup`. Two Windows settings, both before step 2:

- **npm must run package scripts with Git's bash.** Both repositories' scripts are written for a
  Unix shell, and npm on Windows uses `cmd.exe` unless told otherwise. `./push` and `./deploy` set
  this for themselves; for running `npm` by hand (steps 3 to 5), **ask the person**, then:
  `npm config set script-shell "$(cygpath -w "$(command -v bash)")"`. It changes npm for this
  Windows user only.
- **Line endings stay as committed.** Step 2 clones with `--config core.autocrlf=false`. Without it,
  Git for Windows rewrites every file with Windows line endings, the bash commands here break, and
  the repositories' formatting checks fail on every file.

The three repositories are public, so cloning needs no GitHub sign-in. Pushing does: the person signs
in to GitHub on this machine before the first `./push`.

### Installing or upgrading Node

**If `node` is missing or older than 26, ask the person before installing anything.** Say what is
installed now, what you would install and how, and wait for a yes. Use the system's usual route:

| System  | Install                                                                                   |
| ------- | ----------------------------------------------------------------------------------------- |
| macOS   | the current installer from nodejs.org, or `brew install node` if Homebrew is already used |
| Windows | `winget install OpenJS.NodeJS`                                                            |

If the person says no, stop: nothing later works without it. Never change either repository's
`engines` setting to fit an older Node. After installing, open a new terminal if `node --version`
still shows the old version, then carry on.

### On a machine that already runs the system elsewhere

The bootstrap builds a separate copy: its own clones, its own local database and its own
`.dev.vars`, all inside this directory, so it never touches another checkout or its database. Two
things are shared across the whole machine, though, and both bite only while two copies run at once:

- **The ports**, 8787 and 5173.
- **Wrangler's dev registry** (one per user), which finds the local server by its name,
  `foodbank-server`. With two local servers of that name running, a client can reach the wrong one.

So before step 3, **stop any other copy's local server and client.** Nothing may be listening on
either port — on macOS `lsof -iTCP:8787 -iTCP:5173 -sTCP:LISTEN` prints nothing; on Windows
`netstat -ano | grep -E ':(8787|5173) .*LISTENING'` prints nothing. Ask the person rather than
stopping anything yourself.

## 2. Clone the application repositories

From this directory (the `foodbank` project directory):

```bash
git clone --config core.autocrlf=false https://github.com/sapientit/foodbankclient.git foodbankclient
git clone --config core.autocrlf=false https://github.com/sapientit/foodbankserver.git foodbankserver
```

`core.autocrlf=false` keeps the files exactly as committed on every system; on macOS it changes
nothing, on Windows it is essential (step 1).

**The folder names matter.** The client reaches the server as `../foodbankserver`, so both must be
cloned under exactly these names, side by side, inside this directory. Do not use submodules.

**Check:** `git -C foodbankclient status` and `git -C foodbankserver status` both report a clean
working tree on their default branch — **`master` for the client, `main` for the server**; the two
differ — and `git status` here does not list either folder (they are ignored).

### Mark this as the secondary machine

```bash
touch secondary.local foodbankclient/secondary.local foodbankserver/secondary.local
git -C foodbankclient config core.hooksPath ../githooks
git -C foodbankserver config core.hooksPath ../githooks
```

These empty, gitignored files mark this as the secondary machine — one here, and one in each
application repository, so that each repository knows it without depending on where it was cloned.
Each repository's `CLAUDE.md` checks for its own file and, if it exists, sends the session to that
repository's instructions for the secondary machine; [`secondary.md`](./secondary.md) holds the
rules shared by both. **Never create them in Pete's own working copies** (his checkouts outside
this directory), where a push is just a push. A copy bootstrapped here, even on Pete's machine to
trial this route, is marked: following the route is the point of it.

The markers only work if whoever is working here reads them. **The two `git config` lines make git
enforce the rules that matter**, whoever or whatever is at the keyboard — a person, Claude, Codex or
anything else. They point both application repositories at the hooks in [`githooks/`](./githooks/),
which come with this repository:

- **`pre-push`** refuses a plain `git push`. Pushing goes through `./push`, which runs both
  repositories' checks and records the pair it tested; a pair pushed any other way cannot be
  deployed from this machine.
- **`pre-commit`** refuses a commit while a deploy is running or waiting for the night, which would
  otherwise find the repository changed and stand down.

The setting is local to each clone, so it never shows as a change, and the hooks are the committed
files here, so a fresh clone of this repository brings them. `./push` refuses to run, and
`./check-setup` reports the machine `NOT READY`, on a marked machine without them.

**Check:** `ls secondary.local foodbankclient/secondary.local foodbankserver/secondary.local` finds
all three; `git -C foodbankclient config core.hooksPath` and `git -C foodbankserver config
core.hooksPath` both print `../githooks`; and `git status` here and in both repositories lists none
of the markers.

## 3. The server

```bash
cd foodbankserver
npm ci                       # exact versions from package-lock.json
npm run check                # typegen, typecheck, lint, format, contract, tests, deploy dry-run
```

- **`npm run check` must pass.** It needs no Cloudflare credentials and no local configuration — CI
  runs the same command with neither. If it fails on a fresh clone, report it; never weaken a rule
  to make it pass.

### Local configuration

The server needs one local file, `foodbankserver/.dev.vars` (gitignored), holding a signing secret
for local sign-in tokens. It is generated here and used by nothing but this machine's local server,
so it is not a credential in the sense of the rule above. From `foodbankserver`:

```bash
sed "s/^AUTH_JWT_SECRET=.*/AUTH_JWT_SECRET=$(node -e 'console.log(crypto.randomUUID()+crypto.randomUUID())')/" \
  .dev.vars.example > .dev.vars
```

Nothing else in it needs setting for local development: sign-in uses the dummy provider, text
messages are simulated, and the referral form has no bot check. The file's own comments explain the
optional values. **Do not copy a `.dev.vars` from another machine** — it may hold real keys.

### The local database

The development database starts from a snapshot of UAT — a plain `wrangler d1 export`. **It is not in
this repository**, which is public: the snapshot holds staff accounts. It is kept in the charity's
Google Drive, and the technicians' handover guide (**"Food Bank System — Handover Guide"**, section
"Setting up a machine") has the link.

1. **Ask the person to download it** from that link and save it in this directory as
   `seed/uat.sql`. The `seed/` folder is ignored by git, so it can never be committed. Do not look for
   the link yourself, and never write it into a committed file.
2. **Stop here until the file exists.** This is a hard gate: an AI must ask the person for the dump,
   not create an empty database, use another machine's database, or run `db:migrate:local` as a
   substitute. From this project directory, check it without reading or printing its contents:

```bash
./require-seed
```

3. Restore through the guarded project command:

```bash
./restore-local-database
```

This creates the tables, loads the rows, applies any migrations newer than the snapshot and makes
**`pete@x.com`** an active admin, the address the dummy sign-in uses. It refuses to run while the
server is running. Run it again whenever a fresh snapshot is wanted; the database it replaces is
moved to `foodbankserver/.wrangler/state/v3/d1.before-restore-<time>`, not deleted.

**There is no empty-database fallback.** Without `seed/uat.sql`, local setup is incomplete and the
agent stops for the person. The snapshot is deliberately required so local development begins with
the controlled UAT data shape and the staff accounts it needs.

### Start it

```bash
npm run dev                  # http://localhost:8787
```

**Check:**

1. `curl -s http://localhost:8787/health` answers `{"status":"ok",...}`.
2. Signing in as `pete@x.com` returns an `accessToken`:

   ```bash
   curl -s -X POST -H 'content-type: application/json' -d '{"email":"pete@x.com"}' \
     http://localhost:8787/api/v1/auth/dev-login
   ```

## 4. The client

```bash
cd foodbankclient
npm ci                       # exact versions from package-lock.json
npm run cf-typegen           # writes worker-configuration.d.ts from wrangler.jsonc
npm run check                # typecheck, lint, format, API types, dry-run build, tests
```

- **`npm run check` must pass.** It needs no Cloudflare credentials. It compares the client's
  generated API types against `../foodbankserver/openapi.yaml`, which is why the server must be
  cloned first. If it fails on a fresh clone, report it; never weaken a rule to make it pass.
- **No local configuration file is needed.** With nothing set, local development shows the dummy
  sign-in screen and has no bot check on the referral form, which is what local development wants.
  The optional file is `foodbankclient/.env.development.local` (gitignored); its own comments
  explain each value. **Never create `.env.local`**: Vite loads it into production builds too, and it
  would ship a test value to production.
- `npm run check` leaves a **production** build in `dist/`. That is expected; `npm run dev` does not
  use it.

**Check:** `npm run check` exits 0.

## 5. Run the system

Start the server first (step 3, `npm run dev` in `foodbankserver`, port 8787) and **wait until
`curl -s http://localhost:8787/health` answers**. Only then, in a second terminal:

```bash
cd foodbankclient
npm run dev                  # http://localhost:5173
```

- **Use `http://localhost:5173`, never `127.0.0.1`.** They are different sites to a browser, and the
  sign-in cookie only works on one origin.
- **Port 5173 must be free.** The client refuses to fall back to another port; stop whatever holds
  it.
- The client's built-in proxy forwards `/api/*` to the local server through wrangler's dev registry.
  It finds the server by its local Worker name, `foodbank-server`. If API calls fail while both are
  running, first check that `npx wrangler --version` gives the same version in both repositories.

**Check:**

1. `curl -s -i http://localhost:5173/api/v1/public/sessions` returns `content-type:
   application/json` through the client's proxy. **If it returns the app's HTML page instead, the
   client was started before the server was ready**: the request fell through to the app rather
   than reaching the API. Stop the client, confirm the server's `/health` answers, and start the
   client again. (Seen and confirmed while writing this, 2026-10-08.)
2. Open `http://localhost:5173` and sign in as **`pete@x.com`**, the admin the server's step 3 sets
   up. Only addresses that are already active users can sign in; any other is refused — that is
   correct, not a broken sign-in. The admin menu appears.
3. Optional: to see the team lead's screens, add a user with the team lead role at `/users`, then sign
   in as them. There is deliberately no seeded team lead.

## 6. Confirm who is told UAT deploy results

While this route has test and UAT only, **UAT deploys email their result; test deploys do not.** The
recipients are **not** in this repository, which is public: the current list is in the technicians'
handover guide, **"Food Bank System — Handover Guide"**, section "Setting up a machine", as a line
beginning `RESEND_TO=`.

1. **Ask the person to open that guide and paste the `RESEND_TO=` line.** Do not guess or invent
   addresses, and do not look for the guide yourself. If `deploy.local` already exists, show its
   `RESEND_TO` and ask whether it still matches the guide.
2. **Show the addresses back** and ask the person to confirm them.
3. **Write `deploy.local`:** `RESEND_FROM` as in `deploy.local.example`, and the confirmed
   `RESEND_TO`. `deploy.local` is ignored by git and stays on this machine.

**Never write a recipient address into any committed file**, here or in either application
repository, and never put the guide's link in one: anyone with the link can read the guide.

**Check:** `deploy.local` exists, and its `RESEND_TO` is the line the person pasted and confirmed.

## 7. Check push and deploy access

```bash
./check-setup
```

It checks, without showing any credential, that the charity's Cloudflare token is in this
computer's credential store (the keychain on macOS, Credential Manager on Windows) and reaches UAT's
databases, Workers and Turnstile widget; on this machine, that both application repositories run
the hooks from step 2; that the Resend key is stored and
accepted; and that `deploy.local` says who is told a deploy's result. It also says whether Pete's
personal account is signed in, which only `./deploy test` needs.

**"READY"** means this machine can push and deploy to UAT. **Anything `MISSING` — a missing Resend
key included — means the machine is NOT READY**, however well everything else went: without the
Resend key nobody would hear whether an overnight deploy worked.

**Every other step still runs.** A missing credential does not stop the bootstrap; it stops the
machine being ready. Do not try to supply a credential yourself. **Begin your final report with a
line of its own** — `NOT READY: <each MISSING item>` — before anything that went well, and tell the
person to complete those items from "Once, when the machine is set up" in `deploying.md`, then run
`./check-setup` again.

**Run this final check from the person's normal Terminal or Git Bash, not from a restricted AI
terminal.** An AI sandbox can be denied access to the macOS Keychain or Windows Credential Manager;
in that case it can report a stored credential as `MISSING`. That result proves only that the
sandbox could not read the credential store. The person runs `./check-setup` themselves to decide
whether a credential is genuinely missing; do not tell them to replace or re-enter a credential
based only on the restricted check.

**Check:** `./check-setup` ends with `READY`. If it does not, the bootstrap is not complete, and the
final report opens with `NOT READY` and the missing items.

## 8. Leave every repository clean

Everything the bootstrap created — clones, markers, `.dev.vars`, the local database, build output,
logs — must be ignored by git, not left as changes. Different agents carry the steps out in
different ways, so check every time rather than assume:

```bash
git status --porcelain
git -C foodbankclient status --porcelain
git -C foodbankserver status --porcelain
```

**All three must print nothing.** If one prints a file:

- **In this repository:** if it is not a genuine fix, add a pattern for it to `.gitignore` and
  commit that — the `.gitignore` change is the genuine fix. Never delete the file to hide it.
- **In `foodbankclient` or `foodbankserver`:** do not change that repository from here. Report the
  file and how it was made, so that a session in that repository can add it to its `.gitignore`.
- **A tracked file shown as modified** is not a temporary file: something changed it. Report it; do
  not ignore it or reset it.

**Check:** all three commands print nothing, or the person has the list of what did not.

## 9. Where to work next

- **Start AI sessions inside `foodbankclient/` or `foodbankserver/`**, never in this directory, for
  any change to the application. Each repository's `CLAUDE.md` is the starting point for work there.
- Changes to the bootstrap, push or release commands are made here; see [`AGENTS.md`](./AGENTS.md).

## Done when

- [ ] Node 26 or newer, and both application repositories cloned under their exact names.
- [ ] `npm run check` passes in `foodbankserver`, and the server's local checks in step 3 pass.
- [ ] `npm run check` passes in `foodbankclient`.
- [ ] The client on `http://localhost:5173` reaches the local API and `pete@x.com` can sign in.
- [ ] The person has confirmed who is told deploy results, and `deploy.local` holds it (step 6).
- [ ] `git status --porcelain` prints nothing in all three repositories (step 8).
- [ ] `./check-setup` reports `READY`. **Until it does, this machine is NOT READY to push or deploy**,
      and the final report says so first, listing each missing item.
