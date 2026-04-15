#ifndef __KSU_H_KSUD
#define __KSU_H_KSUD

#include <linux/compat.h>
#include <linux/types.h>
#include <asm/syscall.h>

struct filename;
struct inode;

#define KSUD_PATH "/data/adb/ksud"

struct user_arg_ptr {
#ifdef CONFIG_COMPAT
	bool is_compat;
#endif
	union {
		const char __user *const __user *native;
#ifdef CONFIG_COMPAT
		const compat_uptr_t __user *compat;
#endif
	} ptr;
};

void ksu_ksud_init();
void ksu_ksud_exit();

void ksu_execve_hook_ksud(const struct pt_regs *regs);
void ksu_handle_execveat_ksud(const char *path, struct user_arg_ptr *argv);
void ksu_handle_sys_read(unsigned int fd);
int ksu_handle_devpts(struct inode *inode);
void ksu_stop_input_hook_runtime(void);

extern bool ksu_init_rc_hook;
extern bool ksu_execveat_hook;
extern bool ksu_input_hook;
extern const size_t ksu_rc_len;

#endif
