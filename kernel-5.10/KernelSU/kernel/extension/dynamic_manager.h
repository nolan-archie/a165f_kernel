// SPDX-License-Identifier: GPL-2.0
#ifndef __KSU_H_EXTENSION_DYNAMIC_MANAGER
#define __KSU_H_EXTENSION_DYNAMIC_MANAGER

/* Extension adapter over the existing dynamic manager implementation. */
#include "extension.h"
#include "manager/dynamic_manager.h"

int ksu_extension_dynamic_manager_get(u32 id, u64 *value);
int ksu_extension_dynamic_manager_set(u32 id, u64 value);
int ksu_extension_dynamic_manager_io(u32 id, void __user *raw);

extern const struct ksu_extension_handler_ops ksu_extension_dynamic_manager_ops;

#endif /* __KSU_H_EXTENSION_DYNAMIC_MANAGER */
