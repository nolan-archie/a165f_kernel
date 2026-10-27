#ifndef __KSU_BUILTIN_NEW_COMPAT_H
#define __KSU_BUILTIN_NEW_COMPAT_H

/* Compatibility helper used by builtin-new manager sources but absent from
 * this older KernelSU kernel tree. */
#include <linux/slab.h>

#ifndef __offstack
static inline void ksu_compat_kfree_byref(void *buffer)
{
	kfree(*(void **)buffer);
}
#define __offstack(size) \
	__attribute__((__cleanup__(ksu_compat_kfree_byref))) = \
	kmalloc((size), GFP_KERNEL | __GFP_NOFAIL)
#endif

#endif /* __KSU_BUILTIN_NEW_COMPAT_H */
