# Working on the secondary machine

You are reading this because a `secondary.local` marker exists: this is the charity's secondary
machine, set up by [`bootstrap.md`](./bootstrap.md) for emergency fixes. These rules apply to every
AI session here, whichever application repository it started in, and override that repository's own
instructions on pushing. Pete's own working copies, outside this directory, have no marker and
none of this applies to them; a trial copy bootstrapped here on his machine is marked and follows
these rules.

## Before starting work

- **Fetch both application repositories and compare them with GitHub.** If either is behind its
  default branch, say so and pull before changing anything. Read the default branch from GitHub
  (`git ls-remote --symref origin HEAD`); the client's and the server's differ.
- If pulling would conflict with local changes, stop and ask the person. Do not resolve it by
  discarding either side.

## Pushing

**"Push" means the project's push command, never `git push`.** The push command:

1. runs both repositories' full checks, and stops if either fails;
2. pushes the client and the server together;
3. records the tested pair — the client and server commits it checked — on this machine, which is
   what a deploy later insists on.

So never run `git push` in either repository, never push one repository on its own, and never force a
push. A pair pushed any other way cannot be deployed from this machine.

**The push command is `./push`, in this directory.** It takes several minutes, because it runs both
repositories' full checks. If it refuses, report why; never work around it.

## Deploying

Deploying is the person's job, through the deploy command described in
[`deploy-spec.md`](./deploy-spec.md). Do not run it, and never deploy or migrate a database by any
other route from a session here.
