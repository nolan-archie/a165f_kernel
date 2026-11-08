// SPDX-License-Identifier: GPL-2.0
/* Expose the already-integrated SuSFS runtime switches through KSU features. */
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/types.h>

#include <linux/susfs.h>

#include "policy/feature.h"
#include "uapi/feature.h"
#include "klog.h" // IWYU pragma: keep

#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
static int susfs_mount_hide_get(u64 *value)
{
	*value = susfs_is_hide_sus_mnts_enabled();
	return 0;
}

static int susfs_mount_hide_set(u64 value)
{
	return susfs_set_hide_sus_mnts_enabled(value != 0);
}

static const struct ksu_feature_handler susfs_mount_hide_handler = {
	.feature_id = KSU_FEATURE_MOUNT_HIDE,
	.name = "mount_hide",
	.get_handler = susfs_mount_hide_get,
	.set_handler = susfs_mount_hide_set,
};
#endif

#ifdef CONFIG_KSU_SUSFS
static int susfs_avc_spoof_get(u64 *value)
{
	*value = susfs_avc_log_spoofing_is_enabled();
	return 0;
}

static int susfs_avc_spoof_set(u64 value)
{
	return susfs_set_avc_log_spoofing_enabled(value != 0);
}

static const struct ksu_feature_handler susfs_avc_spoof_handler = {
	.feature_id = KSU_FEATURE_AVC_SPOOF,
	.name = "avc_spoof",
	.get_handler = susfs_avc_spoof_get,
	.set_handler = susfs_avc_spoof_set,
};
#endif

void __init ksu_susfs_features_init(void)
{
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (ksu_register_feature_handler(&susfs_mount_hide_handler))
		pr_err("Failed to register SuSFS mount-hide feature\n");
#endif
#ifdef CONFIG_KSU_SUSFS
	if (ksu_register_feature_handler(&susfs_avc_spoof_handler))
		pr_err("Failed to register SuSFS AVC-spoof feature\n");
#endif
}
