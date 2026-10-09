# Deploying

How a person deploys the food bank system with `./deploy`, in plain steps. What the deploy does, and
why, is in [`deploy-spec.md`](./deploy-spec.md). No AI is needed for any of this.

**It runs on macOS or Windows.** On macOS, use Terminal; **on Windows, use Git Bash** (it comes with
Git for Windows), never Command Prompt or PowerShell. Every command below is the same on both.

**Environments on this route: `test` and `uat`.** Production joins after go-live.

## Once, when the machine is set up

1. **Set up the machine** with [`bootstrap.md`](./bootstrap.md).
2. **Store the credentials.** Each command asks for the value without showing it and stores it in
   this computer's own credential store — the keychain on macOS, Credential Manager on Windows.
   Nothing is written to a file. Storing one again replaces it.

   ```bash
   # The charity's Cloudflare API token (needed for UAT).
   ./store-secret foodbank-charity-cloudflare-api-token
   # The Resend API key (needed for every deploy: it sends the result email).
   ./store-secret foodbank-resend-api-key
   ```

   To see or remove them later: on macOS, Keychain Access; on Windows, Control Panel → Credential
   Manager → Windows Credentials.

   For **test**, sign in to Pete's personal Cloudflare account with `npx wrangler login` instead. Only
   Pete can.

3. **Say who is told the result.** The bootstrap asks you to paste the `RESEND_TO=` line from the
   technicians' handover guide ("Setting up a machine") and writes `deploy.local`. To change it
   later, edit `deploy.local` (it is not committed). **Never put an address in any committed file**:
   this repository is public.
4. **Check it all works:** `./check-setup`. It tests each of the above without showing a credential
   and ends with `READY`, or lists what is still missing.

## Every deploy

### 1. Push

```bash
./push
```

It refuses if either repository has uncommitted changes or is behind GitHub (pull first), runs both
repositories' full checks — the server's, then the client's, which also checks the client against the
server's API — and only if both pass pushes whichever has anything to push. It then records the
pair it tested in `tested-pair.local`. **A deploy refuses any pair that file does not name.** The
checks take several minutes.

With nothing to push — after pulling work pushed from another machine — it still runs the checks and
records the pair. That is how this machine comes to trust a pair it did not push.

If it says **only one repository was pushed**, GitHub holds a pair that was never tested together,
and nothing was recorded, so `./deploy` will refuse it. Usually someone pushed first: pull, then run
`./push` again.

**Never use `git push` for the client or the server on this route**: it skips the checks and records
nothing.

### 2. Prepare, in the evening

```bash
./deploy uat          # or: ./deploy test
```

It checks everything and builds, then stops for you at three points:

- **"Type yes once it has arrived"** — check the test email reached the recipients.
- **"Type overnight, now, or anything else to stop"** — press Enter for **overnight**, the normal
  choice. Type **now** only in an emergency (below).

**Overnight**, it says when it will deploy (04:17 London time) and returns. Until then:

- **Leave the computer on mains power, awake and logged in, with the lid open.** The deploy keeps it
  from going to sleep by itself, but closing a laptop's lid, or a power cut, still sends it to sleep.
  If it sleeps through the night, the deploy does not happen; if it wakes after 07:00, it does not
  start then either.
- **On Windows, also keep Windows Update from restarting it overnight** (Settings → Windows Update →
  Active hours, or pause updates for the night), and leave the Git Bash window open.
- **Do not commit, pull or switch branch** in any of the three repositories. The deploy would find
  them changed and stand down.

`./deploy status` shows whether a deploy is waiting.

### 3. In the morning

**Read the result email.** "succeeded" needs nothing more. "FAILED" says which step stopped, what is
live, and — if the database was migrated — the steps to go back (below). **No email at all means
the deploy did not run**; `./deploy status` and the log in `.deploy/` say why.

## Deploying now, in an emergency

At the approval, type **now**. You are warned that people may be using the system, and asked to type
`deploy now`; if the deploy migrates the database, you are warned again and asked to type `migrate`.
It then deploys straight away, while you watch. The result is still emailed.

## If a deploy fails after migrating

The command never repairs anything itself. From this directory, for UAT —
`./charity-wrangler` runs wrangler against the charity's account with the stored token
(`foodbankserver/docs/operations/release-pipeline.md` has the detail):

1. **Take a fresh bookmark first**, so the restore can itself be undone:
   `./charity-wrangler d1 time-travel info foodbank-test --env uat --json`
2. **Put the server back:** `./charity-wrangler rollback --env uat`
3. **Restore the database** to the bookmark in the failure email:
   `./charity-wrangler d1 time-travel restore foodbank-test --env uat --bookmark <bookmark>`
4. **Check** that `referrals`, `stock_ledger` and `users` exist and that
   `https://api-test.guildfordfoodbank.workers.dev/ready` answers.

For test (Pete's own account), run the same three commands as `npx wrangler …` from
`foodbankserver`, with `--env ""` in place of `--env uat`.

**A restore replaces the whole database**: anything written since the bookmark is lost. At 07:00,
after an overnight deploy, that should be nothing. Later in the day it is real work, and fixing
forward may be the better choice.
