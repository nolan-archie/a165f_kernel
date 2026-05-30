# Weekly Kernel Automation: SukiSU + SUSFS

This setup automates the tedious parts of keeping the A165F kernel up to date. Every Monday at 00:00 UTC, a GitHub Action fires off to sync with upstream SukiSU and SUSFS, patches the source, and builds fresh images for both `suki-su-latest` and `permissive` branches.

## What’s Under the Hood?

### 1. The Update Engine (`scripts/automate_updates.sh`)
This script does the heavy lifting before the build starts:
*   **Upstream Sync:** It pulls the latest commits from SukiSU-Ultra and SUSFS.
*   **Bridge Protection:** It backs up our device-specific `susfs_bridge.c` before syncing KernelSU, ensuring we don't lose local fixes.
*   **Surgical Patching:** It finds the `reboot` syscall handler in `supercall.c` and injects the SUSFS dispatch logic. It’s designed to be robust—if the upstream code shifts too much and the patch fails, the build stops rather than producing a broken kernel.
*   **Auto-Changelog:** It generates a summary of upstream changes to include in the GitHub Release notes.

### 2. Space Management (`scripts/maximize_space.sh`)
GitHub’s default runners are cramped. This script nukes unnecessary pre-installed bloat (Android SDKs, .NET, etc.) to free up ~30GB, giving the compiler and toolchain plenty of breathing room.

### 3. CI Workflow (`.github/workflows/kernel_builder.yml`)
The orchestrator. It handles the build matrix, sets up the environment, runs the update script, and pushes code changes back to the repo if new upstream commits were found.

## Manual Triggers

If you don't want to wait for Monday:
1. Go to the **Actions** tab in the repo.
2. Select **Weekly Kernel Builder**.
3. Click **Run workflow** and pick your branch.

## Maintenance Notes

*   **Failure on Patching:** If the `automate_updates.sh` script fails with "Could not find KSU_INSTALL_MAGIC2", it means SukiSU upstream changed their `supercall.c` structure. You'll need to update the `LINE_NUM` logic in the script.
*   **Toolchain:** The build still relies on the `build.sh` logic to fetch the toolchain. Ensure the URL in `build.sh` remains valid.
*   **Git Identity:** All automated commits are signed by `github-actions[bot]`. Manual commits from your local machine will use your configured identity.

---
*Built for the A165F community.*
