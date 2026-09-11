# CI Pipeline Changes — September 2026

This document explains the CI/CD changes made to `a165f_kernel` and the
companion `KernelSU-Next2` manager repo, and the reasoning behind each one.
Two repos are involved because they serve different purposes: this repo
builds the kernel itself, while `KernelSU-Next2` builds the KernelSU-Next
manager APK that pairs with it.

## 1. Cross-repo trigger: kernel build → manager APK build

**Problem:** The manager APK (built in `KernelSU-Next2`) had no way to know
when a new kernel build was ready. The two pipelines ran on independent
schedules with no relationship between them.

**Fix:** `weekly-kernel-build.yml` now fires a `repository_dispatch` event
at `KernelSU-Next2` immediately after a successful `main`-branch build:

```yaml
- name: Trigger KernelSU-Next2 manager build
  if: matrix.branch == 'main' && steps.build.outputs.status == 'success'
  env:
    GH_TOKEN: ${{ secrets.CROSS_REPO_TOKEN }}
  run: |
    curl -s -X POST \
      -H "Authorization: Bearer ${GH_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/repos/nolan-archie/KernelSU-Next2/dispatches \
      -d '{"event_type":"kernel-build-complete"}'
```

**Why `main` only, not `susfs-dev`:** `main` pins KernelSU-Next as its root
management solution. `susfs-dev` uses SukiSU-Ultra instead and has no
KernelSU-Next component at all — triggering a manager rebuild off a
`susfs-dev` build would be triggering it for an unrelated change. The
condition is scoped with `matrix.branch == 'main'` for exactly this reason.

**Why a PAT (`CROSS_REPO_TOKEN`) instead of the default `GITHUB_TOKEN`:**
GitHub's automatic per-run token is scoped to the repo the workflow runs
in — it cannot authenticate against a *different* repository's API. A
fine-grained PAT scoped only to `KernelSU-Next2` with `Actions: write`
permission was the minimum-privilege way to allow this one cross-repo call.

**On `KernelSU-Next2`'s side**, `build-manager-ci.yml` was updated to listen
for that event:

```yaml
on:
  ...
  repository_dispatch:
    types: [kernel-build-complete]
```

This runs the *entire* existing build pipeline (LKM, ksud, both manager
variants) exactly as if it had been triggered by a push — nothing about the
build logic itself changed, only what can invoke it.

## 2. `.gitignore` was silently blocking `.github/`

**Problem:** This repo uses the standard upstream Linux kernel
`.gitignore`, which contains a blanket `.*` rule (ignore all dotfiles) with
only `!.gitignore`, `!.mailmap`, and `!.cocciconfig` carved back out as
exceptions. `.github/` was never added to that exception list, so
`git add .github/workflows/...` was silently rejected — the file existed on
disk but git refused to stage it without `-f`.

**Fix:** Added `!.github/` immediately after the existing `!.cocciconfig`
exception line, so workflow files under `.github/` are tracked normally
going forward without needing to force-add them.

## 3. `KernelSU-Next2` Telegram notifications — main build only

**Problem:** The manager build matrix builds two variants per run — a
"main" (normal package ID) build and a "spoofed" (alternate package ID)
build. Both were independently uploading to the Telegram group, producing
two messages per run.

**Fix:** Added `matrix.spoofed == false` to the `if:` condition on both the
"Bot session cache" and "Upload to telegram" steps in `build-manager-ci.yml`
(dev branch) and `build-manager.yml` (stable branch). The spoofed variant
still builds and is still uploaded as a GitHub Actions artifact — it just no
longer posts to Telegram. One run now produces one message.

## 4. `KernelSU-Next2` weekly upstream sync

**Problem:** `KernelSU-Next2` is a fork of `pershoot/KernelSU-Next` and had
no mechanism to pull in upstream changes — it would drift indefinitely
without a manual sync.

**Fix:** Added `weekly-sync.yml`, which runs every Sunday (or on demand):
fetches `pershoot/KernelSU-Next`'s `dev` branch, merges it into the fork's
`dev`, pushes if anything changed, and then calls `build-manager-ci.yml`
directly as a reusable workflow (`uses: ./.github/workflows/build-manager-ci.yml`)
so a fresh sync always produces a fresh build — independent of whether the
merge happens to touch the path filters on the workflow's normal `push`
trigger.

**Why a plain merge instead of a hard reset to upstream:** a hard reset
would silently discard any commits made directly on the fork's `dev` branch.
A merge preserves fork-specific history and only requires manual
intervention (via a failed, clearly-flagged Actions run) if there's an
actual conflict.

## Secrets required

| Secret | Repo | Purpose |
|---|---|---|
| `CROSS_REPO_TOKEN` | `a165f_kernel` | Fine-grained PAT, `Actions: write` on `KernelSU-Next2` only. Fires the cross-repo dispatch. |
| `PAT_TOKEN` | `a165f_kernel` | Pre-existing — used for checkout/push/release in the kernel build itself. |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | both repos | Pre-existing — Telegram notifications. |

## Open item

`kernel_builder.yml` still exists alongside `weekly-kernel-build.yml` in
this repo's `.github/workflows/` and appears to be an unused duplicate of
the same weekly build job. It was left untouched pending a decision on
whether to remove it.
