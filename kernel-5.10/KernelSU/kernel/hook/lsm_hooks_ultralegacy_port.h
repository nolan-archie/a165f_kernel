// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2026 \xx
 *
 * This file is a downstream extension and NOT affiliated, endorsed by,
 * or maintained by the official KernelSU developers.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

/*
 * Old-kernel mount_hide layer for lsm_hooks_ultralegacy.c, kept in this file
 * so the upstream hook file only needs a one-line include and a couple of
 * call-site tweaks.
 *
 * mount_hide installs its /proc/<pid>/{mounts,mountinfo,mountstats} filter
 * from security_file_permission(). That is orthogonal to the init.rc read
 * hook: keep this layer installed even when the read hook lives in the
 * syscall table / branch link / SUSFS inline hook, and after
 * ksu_vfs_read_hook is retired. The captured stock LSM hook is always
 * chained, so no LSM check is lost.
 */

#ifndef __KSU_H_LSM_HOOKS_ULTRALEGACY_PORT
#define __KSU_H_LSM_HOOKS_ULTRALEGACY_PORT

static int ksu_file_permission_mount(struct file *file, int mask)
{
	ksu_mount_hide_file_permission(file, mask);

	if (orig_file_permission)
		return orig_file_permission(file, mask);
	return 0;
}

/* Retire the init.rc read hook, but leave the mount_hide layer in place. */
static void ksu_restore_file_permission_mount(void)
{
	struct security_operations *ops = (struct security_operations *)selinux_ops_addr;
	int ret;

	if (!ops || !orig_file_permission)
		return;

	ret = patch_ro_slot((uintptr_t)&ops->file_permission,
			    (uintptr_t)ksu_file_permission_mount);
	pr_info("LSM: %s: mount_hide layer kept on file_permission ret: %d\n",
		__func__, ret);
}

#endif /* __KSU_H_LSM_HOOKS_ULTRALEGACY_PORT */
