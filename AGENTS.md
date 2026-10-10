# AGENTS.md

**If `secondary.local` exists in this directory, this is the charity's secondary machine: read
[`secondary.md`](./secondary.md) before anything else and follow it.**

This is the **project directory** for the food bank system. It holds the commands that set up a
machine and release the system, and nothing else. The application itself is two separate
repositories, cloned inside this one:

```
foodbank/                  this repository: bootstrap, push and release commands, their docs
├── foodbankclient/        the React client  — https://github.com/sapientit/foodbankclient
└── foodbankserver/        the JSON API      — https://github.com/sapientit/foodbankserver
```

Both are ignored by this repository's `.gitignore`. **Never commit either of them here, and never
turn them into git submodules** — plain clones, by decision.

## Setting up a machine

Follow [`bootstrap.md`](./bootstrap.md). It is written for an AI agent to carry out step by step, and
for a person to check.

## Where to work

- **Application work happens inside `foodbankclient/` or `foodbankserver/`, in a session started in
  that directory.** Each has its own `CLAUDE.md` and rules, and each may see the other only through
  its documentation. A session started here sees both and gets around that rule, so do not change
  either application from here.
- **Work in this directory is the commands** — bootstrap, push and release — and their docs. When a
  command needs something from an application repository, it calls that repository's documented
  `npm run` scripts. It does not reach into its source.

## The design is already written

**[`deploy-spec.md`](./deploy-spec.md) is the source of truth for the deploy command** — what it
does, the overnight default, the emergency "deploy now", and its open points. The push command and
the reasoning behind both are in `foodbankclient/docs/planning/release-pipeline.md`; the server's
side, what it provides to these commands, is in
`foodbankserver/docs/operations/release-pipeline.md`. **Read them before building any command here,
and do not copy any of them into another** — one copy, one place to update. In outline:

- **Push** pushes both application repositories together, only after both repositories' full checks
  pass, and records the tested pair in a gitignored local file. It never pushes this repository: a fix to
  these commands — debugging them on Windows on the secondary machine, say — is pushed separately.
- **Deploy** has a preparation part, with someone online — every check, the build, then an approval —
  and by default deploys unattended overnight on the same machine, at 04:17 London time, and
  emails the result through Resend. A failure waits for a person at 07:00.
- **In an emergency the person can deploy now** instead of overnight, after an extra confirmation.
- A release with migrations records a D1 Time Travel bookmark first, and stops if it cannot.
- The first production migration is run by hand, outside the automated release.

## Rules for anything built here

- **Only Pete settles a requirement.** Unanswered questions go in the design's "Open points" list;
  never answer one yourself.
- **Write for a deployer with no AI.** Every command is documented in plain steps and works without
  an assistant to interpret its output. Nothing depends on scripts kept outside a repository
  (`~/bin`).
- **Credentials live only in the computer's own credential store** — the keychain on macOS, Windows
  Credential Manager on Windows, both reached through `lib/platform.sh` and stored with
  `./store-secret` — never in a file, a repository, a log, a command line or an email. Anything acting on the
  charity's Cloudflare account sets **both** `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`;
  with the token alone, wrangler can silently pick another account.
- **No personal data** in any output, log, email or file these commands write. Referral data stays
  in D1.
- **One set of commands for macOS and Windows.** They are bash, run in Git Bash on Windows. What
  differs between the two systems — credentials, staying awake, npm's script shell — lives in
  `lib/platform.sh` and nowhere else; anything else must work unchanged on both (date arithmetic is
  in Node for that reason: the two `date` commands differ). Linux is not supported.
- **Keep the dependencies to what the system and Git for Windows ship** plus Node (26 or newer) and
  the applications' own `npm` scripts. `curl` sends the Resend email.
- **An AI session never releases to production or migrates the production database.** It may build
  and test the commands against local development and, with Pete's explicit go-ahead, UAT.
- **The local database must be restored from the private UAT snapshot.** During bootstrap, an agent
  runs only `./restore-local-database`, which first requires `seed/uat.sql`. If the snapshot is
  absent, stop and ask the person to download it from the technicians' handover guide. Never create
  an empty local database or use `npm run db:migrate:local` as a bootstrap substitute.
- **Anything an agent creates that is not a deliberate change goes in `.gitignore`.** Generated
  files, local state, logs, markers, temporary files: if it is not a genuine fix to commit, it is
  ignored. Before finishing, `git status --porcelain` prints nothing in this repository and in both
  application repositories. A file that shows up in an application repository is reported, not
  ignored from here: its `.gitignore` is changed by a session in that repository.
- **Never assume a branch name.** The client's default branch is `master` and the server's is `main`.
  A command reads each repository's default branch from GitHub
  (`git ls-remote --symref origin HEAD`) rather than writing either name in.
- **This repository has the same push rules as the other two:** a release refuses to run if this
  repository has uncommitted changes, unpushed commits or is behind GitHub.

## Status

`./push`, `./deploy`, `./check-setup`, `./require-seed` and `./restore-local-database` are built
(`deploying.md` says how a person runs them; `test/` tests their helpers and the secondary machine's
git hooks in `githooks/`). `./push` has been run end to end against stand-in remotes; `./deploy` has
now been prepared and stopped safely on test, but has not completed there or on UAT. Bootstrap
restores the local database only from `seed/uat.sql` — a `wrangler d1 export` of UAT that the person
downloads from the charity's Drive (never committed: `seed/` is ignored) — through
`./restore-local-database`.
