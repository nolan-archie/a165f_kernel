/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __KSU_H_EXTENSION_KPM
#define __KSU_H_EXTENSION_KPM

#include <linux/types.h>

#include "extension.h"

int ksu_extension_kpm_get(u32 id, u64 *value);
int ksu_extension_kpm_io(u32 id, void __user *raw);
void ksu_extension_kpm_apply_forced(u32 id, u64 value);

extern const struct ksu_extension_handler_ops ksu_extension_kpm_ops;

#endif /* __KSU_H_EXTENSION_KPM */
