#ifndef __KSU_H_KSU_CORE
#define __KSU_H_KSU_CORE

/*
 * Legacy compatibility shim for downstream kernels that still include
 * drivers/kernelsu/core_hook.h after the upstream source layout rewrite.
 */
void ksu_escape_to_root(void);

#endif
