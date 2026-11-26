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
 * Old-kernel additions for slow_avc_audit_defs.h, kept in this file so the
 * upstream header only needs a one-line include and a single extra _Generic
 * entry:
 *
 *  - honour avc_spoof when arm64_bl_patch() redirects the avc_has_perm*
 *    call sites here, because the kprobe on slow_avc_audit() never fires
 *    on those kernels (most 3.4 .. 5.4 arm64 builds);
 *  - slow_avc_audit() ABI without the `result` argument (3.5 .. 3.16 and
 *    vendor trees);
 *  - arm32 without kprobes: rewrite every `bl`/`b` to slow_avc_audit in
 *    kernel text with the kernel's own patch_text().
 */

#ifndef __KSU_H_SLOW_AVC_AUDIT_PORT
#define __KSU_H_SLOW_AVC_AUDIT_PORT

#include "../feature/avc_spoof.h"

/*
 * avc_spoof owns its own SIDs and enable switch. When the avc_has_perm*
 * callers are redirected here, its kprobe on slow_avc_audit() is bypassed,
 * so the feature has to be honoured from this path too.
 */
static __always_inline void ksu_slow_avc_audit_port_rewrite(u32 *tsid)
{
	ksu_avc_spoof_rewrite_tsid(tsid);
}

#if defined(CONFIG_AUDIT) && defined(CONFIG_ARM64) && defined(CONFIG_KALLSYMS)

extern typeof(slow_avc_audit) slow_avc_audit;

/* 3.5 .. 3.16 / vendor trees: no `result` argument yet. */
#define SLOW_AVC_AUDIT_TYPE_0	u32 ssid, u32 tsid, u16 tclass, u32 requested, u32 audited, u32 denied, struct common_audit_data *a, unsigned int flags
__overloaded static int ksu_slow_avc_audit_handler_0(SLOW_AVC_AUDIT_TYPE_0)
{
	ksu_slow_avc_audit_inline(&tsid);

	assume(!!&slow_avc_audit);
	return ((typeof(ksu_slow_avc_audit_handler_0) *)(void *)slow_avc_audit)(ssid, tsid, tclass, requested, audited, denied, a, flags);
}

#endif /* CONFIG_AUDIT && CONFIG_ARM64 && CONFIG_KALLSYMS */

#if defined(CONFIG_ARM) && defined(CONFIG_AUDIT) && defined(CONFIG_KALLSYMS) && \
	!defined(CONFIG_CPU_ENDIAN_BE8) && !defined(CONFIG_CPU_ENDIAN_BE32) && \
	!defined(CONFIG_KPROBES)

/*
 * ARM32 without kprobes: rewrite every unconditional `bl`/`b`
 * slow_avc_audit_ in kernel text with the kernel's own patch_text().
 *
 * The trampoline is deliberately signature-agnostic: on ARM the target SID is
 * the second argument (the third once struct selinux_state was prepended),
 * while slow_avc_audit() also gained a `result` argument after 3.10 and
 * gained/lost the flags argument in different trees. It saves r0-r3 and lr,
 * lets the shared inline hook rewrite the saved tsid slot, then tail-branches
 * to the real slow_avc_audit() with the original register/stack arguments and
 * return address. Patching a `b` keeps it a `b` so a tail-called audit keeps
 * its original return address.
 */
extern char _stext[], _etext[];

/*
 * arch/arm/kernel/patch.c; only declared in the private arch/arm/kernel/patch.h
 * on old trees, and patch.o is only linked when CONFIG_JUMP_LABEL or
 * CONFIG_KPROBES is enabled. Resolve it through kallsyms to avoid a hard link
 * reference; kallsyms stores ARM Thumb function addresses with bit 0 clear,
 * but indirect calls need it set.
 */
typedef void (*ksu_arm32_patch_text_fn)(void *addr, unsigned int insn);
static ksu_arm32_patch_text_fn ksu_arm32_patch_text __read_mostly;

void *ksu_arm32_slow_avc_audit_slot __read_mostly;

__attribute__((used, noinline))
void ksu_slow_avc_audit_arm32_hook(u32 *tsid)
{
	ksu_slow_avc_audit_inline(tsid);
}

/* Keep the manual-hook API available on this branch too. */
void ksu_slow_avc_audit(u32 *tsid)
{
	ksu_slow_avc_audit_inline(tsid);
}

/*
 * slow_avc_audit(ssid, tsid, ...) until 4.16; 4.17+ prepends
 * struct selinux_state, so tsid moves to the third argument (saved r2).
 * Keep this in sync with the kprobe argument selection in avc_spoof.c.
 *
 * Layout after push {r0-r3, lr} + sub sp, sp, #4:
 *   sp+0 padding, sp+4 r0, sp+8 r1, sp+12 r2, sp+16 r3, sp+20 lr
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0) && \
	(LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0) || defined(KSU_COMPAT_HAS_SELINUX_STATE))
#define KSU_ARM32_TSID_SAVED_OFFSET "12"
#else
#define KSU_ARM32_TSID_SAVED_OFFSET "8"
#endif

__attribute__((naked, used, noinline))
static void ksu_arm32_slow_avc_audit_trampoline(void)
{
	asm volatile(
		"push	{r0-r3, lr}\n"
		"sub	sp, sp, #4\n"
		"add	r0, sp, #" KSU_ARM32_TSID_SAVED_OFFSET "\n"
		"bl	ksu_slow_avc_audit_arm32_hook\n"
		"add	sp, sp, #4\n"
		"pop	{r0-r3, lr}\n"
		"ldr	r12, 1f\n"
		"ldr	r12, [r12]\n"
		"bx	r12\n"
		".align	2\n"
		"1:	.word	ksu_arm32_slow_avc_audit_slot\n");
}

#undef KSU_ARM32_TSID_SAVED_OFFSET

static int ksu_arm32_patch_slow_avc_audit_calls(uintptr_t target)
{
	uintptr_t start = (uintptr_t)_stext;
	uintptr_t end = (uintptr_t)_etext;
	uintptr_t hook = (uintptr_t)&ksu_arm32_slow_avc_audit_trampoline;
	uintptr_t patch_fn = kallsyms_lookup_retry("patch_text");
	uintptr_t patch_call = patch_fn;
	u8 *buf;
	uintptr_t page;
	int found = 0;
	int patched = 0;

#ifdef CONFIG_THUMB2_KERNEL
	patch_call |= 1UL;
#endif

	if (!start || !end || end <= start || !target || !patch_fn) {
		pr_info("avc_spoof: arm32 hook unavailable (start 0x%lx end 0x%lx target 0x%lx patch_text 0x%lx)\n",
			start, end, target, patch_fn);
		return 0;
	}

	*(void **)&ksu_arm32_patch_text = (void *)patch_call;

	buf = kmalloc(PAGE_SIZE + 8, GFP_KERNEL);
	if (!buf)
		return 0;

	/* Kallsyms returns the raw code address, without the Thumb bit. */
	target &= ~1UL;
#ifdef CONFIG_THUMB2_KERNEL
	ksu_arm32_slow_avc_audit_slot = (void *)(target | 1UL);
#else
	ksu_arm32_slow_avc_audit_slot = (void *)target;
#endif

	for (page = start & PAGE_MASK; page < end; page += PAGE_SIZE) {
		size_t len = end - page;
		size_t off;

		if (len > PAGE_SIZE + 8)
			len = PAGE_SIZE + 8;

		if (copy_from_kernel_nofault(buf, (void *)page, len)) {
			len = end - page;
			if (len > PAGE_SIZE)
				len = PAGE_SIZE;
			if (copy_from_kernel_nofault(buf, (void *)page, len))
				continue;
		}

		cond_resched();

#ifdef CONFIG_THUMB2_KERNEL
		for (off = 0; off + 4 <= len; off += 2) {
			uintptr_t site = page + off;
			u16 hw1, hw2, n1, n2;
			u32 base, s, j1, j2, i1, i2, imm10, imm11, imm25;
			s32 delta;
			long rel;
			int is_bl;

			if (site < start)
				continue;

			hw1 = *(u16 *)(buf + off);
			hw2 = *(u16 *)(buf + off + 2);
			if ((hw1 & 0xf800) != 0xf000)
				continue;

			base = hw2 & 0xd000;
			if (base != 0xd000 && base != 0x9000)
				continue;

			s = (hw1 >> 10) & 1;
			imm10 = hw1 & 0x03ff;
			j1 = (hw2 >> 13) & 1;
			j2 = (hw2 >> 11) & 1;
			i1 = (j1 ^ s) ^ 1;
			i2 = (j2 ^ s) ^ 1;
			imm25 = (s << 24) | (i1 << 23) | (i2 << 22) |
				(imm10 << 12) | ((hw2 & 0x07ff) << 1);
			delta = (s32)(imm25 << 7) >> 7;

			/*
			 * T32 B/BL base is Align(PC, 4), PC being the
			 * instruction address + 4. For a 32-bit instruction at
			 * addr & 2 this is the second halfword's address.
			 */
			if ((uintptr_t)((((long)site + 4) & ~3L) + delta) != target)
				continue;

			found++;

			rel = (long)(hook & ~1UL) - (long)(((uintptr_t)site + 4) & ~3UL);
			if ((rel & 1) || rel < -(1L << 24) || rel > (1L << 24) - 2)
				continue;

			is_bl = (base == 0xd000);
			s = (rel >> 24) & 1;
			i1 = (rel >> 23) & 1;
			i2 = (rel >> 22) & 1;
			j1 = ((i1 ^ 1) ^ s) & 1;
			j2 = ((i2 ^ 1) ^ s) & 1;
			imm10 = (rel >> 12) & 0x03ff;
			imm11 = (rel >> 1) & 0x07ff;
			n1 = 0xf000 | (s << 10) | imm10;
			n2 = (is_bl ? 0xd000 : 0x9000) |
				(j1 << 13) | (j2 << 11) | imm11;

			ksu_arm32_patch_text((void *)site, ((u32)n1 << 16) | n2);
			patched++;
		}
#else
		for (off = 0; off + 4 <= len; off += 4) {
			uintptr_t site = page + off;
			u32 insn, op, newinsn;
			s32 delta;
			long rel;
			int is_bl;

			if (site < start)
				continue;

			insn = *(u32 *)(buf + off);
			op = insn & 0xff000000;
			if (op != 0xea000000 && op != 0xeb000000)
				continue;

			delta = (s32)(insn << 8) >> 6;
			if ((uintptr_t)((long)site + 8 + delta) != target)
				continue;

			found++;

			rel = (long)hook - (long)(site + 8);
			if ((rel & 3) || rel < -(1L << 25) || rel > (1L << 25) - 4)
				continue;

			is_bl = (op == 0xeb000000);
			newinsn = (is_bl ? 0xeb000000 : 0xea000000) |
				((u32)(rel >> 2) & 0x00ffffff);

			ksu_arm32_patch_text((void *)site, newinsn);
			patched++;
		}
#endif
	}

	kfree(buf);

	pr_info("avc_spoof: arm32 hook: found %d site(s), patched %d\n",
		found, patched);

	return patched;
}

static void ksu_init_slow_avc_audit_hook(void)
{
	uintptr_t target;
	int ret = ksu_selinux_get_sids();

	if (ret)
		pr_info("selinux_hide: sid grab fail?\n");

	target = kallsyms_lookup_retry("slow_avc_audit");
	if (!target) {
		pr_info("avc_spoof: slow_avc_audit not found, arm32 hook skipped\n");
		return;
	}

	ksu_arm32_patch_slow_avc_audit_calls(target);
}

#endif /* CONFIG_ARM && CONFIG_AUDIT && CONFIG_KALLSYMS && !KPROBES */

#endif /* __KSU_H_SLOW_AVC_AUDIT_PORT */
