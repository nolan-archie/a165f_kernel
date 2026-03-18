/* SPDX-License-Identifier: GPL-2.0 */
#undef TRACE_SYSTEM
#define TRACE_SYSTEM ksu_trace

#define TRACE_INCLUDE_PATH trace/hooks
#if !defined(_TRACE_HOOK_KSU_TRACE_H) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_HOOK_KSU_TRACE_H

#include <linux/types.h>
#include <linux/tracepoint.h>
#include <trace/hooks/vendor_hooks.h>

#ifdef __GENKSYMS__
struct filename;
#else
#include <linux/fs.h>
#endif

DECLARE_HOOK(ksu_trace_execveat_hook,
	TP_PROTO(int *fd, struct filename **filename_ptr,
		 void *argv, void *envp, int *flags),
	TP_ARGS(fd, filename_ptr, argv, envp, flags));

DECLARE_HOOK(ksu_trace_faccessat_hook,
	TP_PROTO(int *dfd, const char __user **filename_user, int *mode,
		 int *flags),
	TP_ARGS(dfd, filename_user, mode, flags));

DECLARE_HOOK(ksu_trace_sys_read_hook,
	TP_PROTO(unsigned int fd, char __user **buf, size_t *count),
	TP_ARGS(fd, buf, count));

DECLARE_HOOK(ksu_trace_stat_hook,
	TP_PROTO(int *dfd, const char __user **filename_user, int *flags),
	TP_ARGS(dfd, filename_user, flags));

DECLARE_HOOK(ksu_trace_input_hook,
	TP_PROTO(unsigned int *type, unsigned int *code, int *value),
	TP_ARGS(type, code, value));

#endif /* _TRACE_HOOK_KSU_TRACE_H */
/* This part must be outside protection */
#include <trace/define_trace.h>
