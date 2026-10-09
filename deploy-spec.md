# Deploy specification

**The source of truth for the deploy command built in this directory.** It says what the charity
wants the deploy to do, not how the code does it. The reasoning behind the design, and how it was
reached, is in `foodbankclient/docs/planning/release-pipeline.md`; where the two disagree, this file
wins. Only Pete settles a requirement here. Unanswered questions go in [Open points](#open-points),
and nobody else closes them.

**Status: built (`./deploy`; how a person runs it is in [`deploying.md`](./deploying.md)), not yet tried on test or UAT, and unusable until the push command exists to write the tested-pair record.**

## What a deploy is

A deploy puts one tested pair — a client commit and a server commit — live on one environment, **UAT**
or **production**. The client and server are always deployed together, as a pair, and only a pair
that is exactly what is on GitHub.

**This is the emergency route, and a simple one.** Pete's own deploy scripts stay as they are for
primary development and are not part of it; nothing here may change them or stop the repositories
being deployed by them. Every script for this route lives in this repository.

**Until go-live the route deploys to test and UAT.** Test is on Pete's personal Cloudflare account,
reached through his own Wrangler sign-in, so that he can try the route on his own; nobody else has
access to it, and it stops being relevant after go-live. Production joins the route later.

A deploy has two parts, run on the same machine:

- **Preparation**, with a person present: every check, the build, and an approval.
- **The deploy itself**: migrate, deploy, verify, record and report.

**By default the deploy itself runs overnight, unattended.** In an emergency, the person can choose
to **deploy now** instead. Both are described below; they differ only in when the deploy itself runs
and in what the person is asked to confirm.

## Before a deploy can be prepared

- **The tested pair has been recorded on this machine** by the push command, which runs both
  repositories' full checks and writes the client and server commits it tested to a gitignored local
  record. A deploy never runs the tests itself; it trusts that record.
- **The machine holds the credentials in its own credential store** (the keychain on macOS,
  Credential Manager on Windows): the charity's Cloudflare API token and the
  Resend API key. Nothing else holds them. The Resend key is needed for UAT, not test.

## Deploy-result emails

**While this route has test and UAT only, UAT is the sole environment that sends deploy emails.**
Test is a private proving ground: its preparation, success and failure are reported in the terminal
and `.deploy/` log, not by email. When production joins the route, production becomes the sole
email environment and this rule is changed in the same release.

## Preparation

Run by a person, in the evening for an overnight deploy. The command:

1. **Confirms all three repositories match GitHub exactly** — the client, the server and this
   project repository: no local changes, nothing unpushed, nothing newer on GitHub not yet pulled.
   Otherwise it stops and says why.
2. **Confirms the pair on GitHub is the pair this machine recorded as tested.** A half-finished push,
   a plain `git push`, or someone else's push this machine has not tested is refused, with a message
   saying to run the push command first.
3. **Shows what will be deployed**: the environment, both commits, the changes since the last deploy
   to that environment, and **any pending database migrations, by name**. For production, it also
   says whether this exact pair has already been deployed to UAT.
4. **Builds both repositories** for that environment. Everything that can be done with the person
   present is done here, the build included. The client's build settings (the bot-check key, the
   sign-in mode, the Google sign-in client) are written in the command rather than remembered; the
   server's are already in its `wrangler.jsonc` for each environment, and the command passes none. The
   deploy itself uses exactly these files and builds nothing.
5. **Checks everything the deploy itself will need**, so it cannot fail for a reason knowable now:
   the Cloudflare token works against the charity's account, the database's Time Travel bookmark can
   be read, and for UAT a test email sent through Resend arrives. Test skips the email check.
6. **Asks the person to choose and approve:**
   - **Overnight (the default)** — schedules the deploy itself for **04:17 London time** that
     night. Nothing on the live system changes until then. That is clear of the server's own nightly
     job in every season (it runs at 02:17 UTC: 02:17 London time in winter, 03:17 in summer) and
     leaves time before 07:00. Starting at the same time as that job would do no great harm; the
     time is chosen to avoid it, not because an overlap must never happen.
   - **Now (emergency only)** — runs the deploy itself immediately, after the extra confirmation in
     [Deploying now](#deploying-now).

   Without approval, nothing is scheduled and nothing changes.

## The deploy itself

The same steps whichever was chosen. For an overnight deploy, the machine that ran the preparation is
left on, awake and online until it has finished.

1. **Confirms GitHub still holds exactly the approved pair**, and that this project repository has
   not changed. If anything has changed since approval, it deploys nothing; for UAT it emails why.
2. **If there are migrations to apply, records a restore point.** It takes the database's current
   Time Travel bookmark and saves it with the deploy record. If the bookmark cannot be taken, it
   stops before migrating. With no migrations pending, this step is skipped.
3. **Applies the server's database migrations, deploys the server, then deploys the client**, from
   the files built during preparation.
4. **Verifies the result**: the deployed commits are the approved ones, the server reports healthy,
   the client loads, and a public API request works through the client. Each check retries for about
   a minute before failing, because just after a deploy the old version can still be served for a few
   seconds.
5. **Records the deploy** by pushing a tag naming the environment and time to both application
   repositories.
6. **For UAT, emails the result through Resend.** Success names the environment and both commits.
   Failure names the step that failed, what is now live, and — if it had migrated — the bookmark and
   the steps to go back. **The email holds no personal data.** Test sends no email; its terminal and
   `.deploy/` log carry the same result.

## Deploying now

For an emergency only: a fix that cannot wait for the night. It is chosen at the approval in
preparation step 6, and runs the deploy itself straight away.

- **The preparation is identical.** Every check and the build run in full; deploying now skips
  nothing that makes a deploy safe.
- **The person must confirm that they understand it is happening while the system may be in use.**
  The command says so plainly before they confirm: someone may be part-way through a referral or a
  session task, nothing can detect that, and they may lose what they were doing.
- **If there are migrations, the command says so separately** and asks again: a migration during
  the day cannot be undone without a database restore, and a restore would lose everything written
  since the bookmark — real referrals, during the day.
- **The person is present, so a failure is theirs to handle there and then.** UAT emails the result;
  test writes it to the terminal and `.deploy/` log.
- **Deploying now needs no special care around the server's nightly job.** An overlap with it does
  no harm worth waiting for or refusing over.

## When a deploy fails after migrating

The migration runs before the new server is deployed. If it fails part-way, or succeeds and the
server deploy then fails, the database and the code no longer match, and putting the server back on
its own does not fix it. The command stops; it never repairs itself. The failure email gives the steps,
in order, for a person to carry out:

1. Take a fresh bookmark, so the restore itself can be undone.
2. Put the server back to the version that was live before the deploy.
3. Restore the database to the deploy's bookmark.
4. Check that `referrals`, `stock_ledger` and `users` exist and the server reports healthy.

**A restore replaces the whole database**, so anything written after the bookmark is lost. After an
overnight deploy, a person deals with the failure at 07:00 and the restore should lose nothing. After
a deploy now, or a problem found later in the day, restoring loses real work, and fixing forward may
be the better choice — a judgement for the person, not the command.

**A Time Travel restore must be rehearsed on UAT before this is relied on.**

## What the deploy never does

- **Never runs the first production migration.** Production's first migration is run by hand and
  watched, outside the deploy. The command refuses a production deploy until that has been done.
- **Never deploys a pair that is not exactly what is on GitHub**, or one this machine has not tested.
- **Never repairs a failure on its own** — no automatic restore, no automatic rollback.
- **Never puts a credential** in a file, a repository, a log, a command line or an email.
- **Never writes personal data** into any output, log, email or file.
- **Is never run by an AI session against production.**

## Open points

Only Pete closes these.

1. **A deploy that never runs sends no email.** If the machine sleeps, loses power or loses its
   connection, the overnight deploy does nothing and tells nobody. Should the absence of a result
   email by 07:00 be treated as a failure, and who checks for it? (Raised 2026-10-08.)
2. **Who may deploy now.** Is the emergency option open to anyone who may deploy, or only to some of
   them? (Raised 2026-10-08.)
3. **Deploying now to production without UAT first.** An emergency fix may not have been deployed to
   UAT. Should deploying now to production still require the pair to have been on UAT, or only warn?
   (Raised 2026-10-08.)
4. **Cancelling an approved overnight deploy.** Should a person be able to withdraw an approval before
   the night? And should a deploy now cancel an overnight deploy already approved for that
   environment? Left alone, that one would find GitHub changed at night, deploy nothing and send a
   failure email for the morning. (Raised 2026-10-08.)
