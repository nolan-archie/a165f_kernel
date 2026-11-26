#!/usr/bin/env python3
"""Adapt builtin-new SUSFS pathname hooks to the Linux 5.10 call sites."""

from pathlib import Path
import sys


if len(sys.argv) != 2:
    raise SystemExit(f"Usage: {Path(sys.argv[0]).name} <path/to/feature/sucompat.c>")

source_path = Path(sys.argv[1])
source = source_path.read_text()
marker = "The 5.10 SUSFS call sites run before user_path_at()"
if marker in source:
    print("[compat] Linux 5.10 SUSFS pathname ABI fix is already applied.")
    raise SystemExit(0)

upstream = '''int ksu_handle_faccessat(int *dfd, struct filename **filename_ptr, int *mode, int *__unused_flags)
{
	struct filename *filename = *filename_ptr;

	if (unlikely(IS_ERR(filename) || filename->name == NULL))
		return 0;

	if (likely(memcmp(filename->name, su_path, sizeof(su_path))))
		return 0;

	pr_info("ksu_handle_faccessat: su->sh!\\n");
	memcpy_inline(filename->name, sh_path, sizeof(sh_path));
	return 0;
}

int ksu_handle_stat(int *dfd, struct filename **filename_ptr, int *flags)
{
	struct filename *filename = *filename_ptr;

	if (unlikely(IS_ERR(filename) || filename->name == NULL))
		return 0;

	if (likely(memcmp(filename->name, su_path, sizeof(su_path))))
		return 0;

	pr_info("ksu_handle_stat: su->sh!\\n");
	memcpy_inline(filename->name, sh_path, sizeof(sh_path));
	return 0;
}
'''

replacement = '''#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0)
int ksu_handle_faccessat(int *dfd, struct filename **filename_ptr, int *mode,
			 int *__unused_flags)
{
	struct filename *filename = *filename_ptr;

	if (unlikely(IS_ERR(filename) || filename->name == NULL))
		return 0;

	if (likely(memcmp(filename->name, su_path, sizeof(su_path))))
		return 0;

	pr_info("ksu_handle_faccessat: su->sh!\\n");
	memcpy_inline(filename->name, sh_path, sizeof(sh_path));
	return 0;
}

int ksu_handle_stat(int *dfd, struct filename **filename_ptr, int *flags)
{
	struct filename *filename = *filename_ptr;

	if (unlikely(IS_ERR(filename) || filename->name == NULL))
		return 0;

	if (likely(memcmp(filename->name, su_path, sizeof(su_path))))
		return 0;

	pr_info("ksu_handle_stat: su->sh!\\n");
	memcpy_inline(filename->name, sh_path, sizeof(sh_path));
	return 0;
}
#else
/*
 * The 5.10 SUSFS call sites run before user_path_at() and pass a userspace
 * pathname pointer. They do not pass struct filename **. Keep these hook
 * ABIs aligned with fs/open.c and fs/stat.c, and only rewrite after a safe
 * copy confirms the exact su path.
 */
int ksu_handle_faccessat(int *dfd, const char __user **filename_user,
			 int *mode, int *__unused_flags)
{
	char path[sizeof(su_path) + 1] = { 0 };

	if (unlikely(!filename_user || !*filename_user))
		return 0;
	if (strncpy_from_user(path, *filename_user, sizeof(path)) < 0)
		return 0;
	if (likely(memcmp(path, su_path, sizeof(su_path))))
		return 0;

	pr_info("ksu_handle_faccessat: su->sh!\\n");
	*filename_user = sh_user_path();
	return 0;
}

int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags)
{
	char path[sizeof(su_path) + 1] = { 0 };

	if (unlikely(!filename_user || !*filename_user))
		return 0;
	if (strncpy_from_user(path, *filename_user, sizeof(path)) < 0)
		return 0;
	if (likely(memcmp(path, su_path, sizeof(su_path))))
		return 0;

	pr_info("ksu_handle_stat: su->sh!\\n");
	*filename_user = sh_user_path();
	return 0;
}
#endif
'''

if source.count(upstream) != 1:
    raise SystemExit(
        "[compat] Expected exactly one unmodified builtin-new pathname hook block; "
        "review the upstream API before applying this 5.10 compatibility fix."
    )

source_path.write_text(source.replace(upstream, replacement, 1))
print("[compat] Applied Linux 5.10 SUSFS pathname hook ABI fix.")
