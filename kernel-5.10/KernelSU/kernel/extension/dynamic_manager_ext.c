// SPDX-License-Identifier: GPL-2.0
/* Unified-extension adapter for the legacy dynamic-manager implementation. */
#include <linux/errno.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

#include "dynamic_manager.h"
#include "klog.h" // IWYU pragma: keep

int ksu_extension_dynamic_manager_get(u32 id, u64 *value)
{
	(void)id;
	if (!value)
		return -EINVAL;
	*value = ksu_manager_enabled();
	return 0;
}

int ksu_extension_dynamic_manager_set(u32 id, u64 value)
{
	struct ksu_manager_cmd *cmd;
	int ret;

	(void)id;
	cmd = kzalloc(sizeof(*cmd), GFP_KERNEL);
	if (!cmd)
		return -ENOMEM;

	cmd->operation = KSU_MANAGER_SET_ENABLED;
	cmd->enabled = !!value;
	ret = ksu_dynamic_manager_set(cmd);
	kfree(cmd);
	return ret;
}

int ksu_extension_dynamic_manager_io(u32 id, void __user *raw)
{
	struct ksu_manager_cmd *cmd;
	int ret;

	(void)id;
	if (!raw)
		return -EFAULT;
	cmd = kzalloc(sizeof(*cmd), GFP_KERNEL);
	if (!cmd)
		return -ENOMEM;
	if (copy_from_user(cmd, raw, sizeof(*cmd))) {
		ret = -EFAULT;
		goto out;
	}

	if (cmd->operation == KSU_MANAGER_GET) {
		ret = ksu_dynamic_manager_get(cmd);
		if (!ret && copy_to_user(raw, cmd, sizeof(*cmd)))
			ret = -EFAULT;
	} else {
		ret = ksu_dynamic_manager_set(cmd);
	}

	out:
	kfree(cmd);
	return ret;
}

const struct ksu_extension_handler_ops ksu_extension_dynamic_manager_ops = {
	.get = ksu_extension_dynamic_manager_get,
	.set = ksu_extension_dynamic_manager_set,
};
