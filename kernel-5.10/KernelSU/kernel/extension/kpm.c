// SPDX-License-Identifier: GPL-2.0
/* Bridge the unified extension API to this tree's existing KPM backend. */
#include <linux/errno.h>
#include <linux/kernel.h>

#include "extension.h"
#include "kpm.h"
#include "kpm/kpm.h"
#include "klog.h" // IWYU pragma: keep

int ksu_extension_kpm_get(u32 id, u64 *value)
{
	if (!value)
		return -EINVAL;
	*value = IS_ENABLED(CONFIG_KPM);
	return 0;
}

const struct ksu_extension_handler_ops ksu_extension_kpm_ops = {
	.get = ksu_extension_kpm_get,
};

int ksu_extension_kpm_io(u32 id, void __user *raw)
{
#ifdef CONFIG_KPM
	return do_kpm(raw);
#else
	(void)raw;
	pr_warn_once("extension/kpm: rebuild with CONFIG_KPM=y to use KPM\n");
	return -EOPNOTSUPP;
#endif
}

void ksu_extension_kpm_apply_forced(u32 id, u64 value)
{
	/* KPM availability is fixed by CONFIG_KPM in this legacy backend. */
	pr_warn_once("extension/kpm: force_extension is not supported by this backend\n");
}
