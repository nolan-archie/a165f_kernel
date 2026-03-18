#include <linux/dcache.h>
#include <linux/security.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <linux/string.h>
#include <linux/types.h>

#include "ksud.h"
#include "selinux/selinux.h"

extern int security_context_to_sid(const char *context, size_t len, u32 *sid);

#define SUSFS_PRIV_APP_CONTEXT "u:r:priv_app:s0:c512,c768"

bool ksu_execveat_hook __read_mostly = false;
bool ksu_input_hook __read_mostly = false;
u32 susfs_ksu_sid __read_mostly = 0;
u32 susfs_priv_app_sid __read_mostly = 0;

static bool is_init_rc_path(struct file *file)
{
	char path[256];
	char *dpath;

	if (!file)
		return false;

	if (strcmp(current->comm, "init"))
		return false;

	if (!d_is_reg(file->f_path.dentry))
		return false;

	dpath = d_path(&file->f_path, path, sizeof(path));
	if (IS_ERR(dpath))
		return false;

	return strcmp(dpath, "/system/etc/init/hw/init.rc") == 0;
}

static void ensure_susfs_sids(void)
{
	int ret;

	if (!susfs_ksu_sid) {
		ret = security_context_to_sid(KERNEL_SU_CONTEXT,
					      strlen(KERNEL_SU_CONTEXT),
					      &susfs_ksu_sid);
		if (ret)
			susfs_ksu_sid = 0;
	}

	if (!susfs_priv_app_sid) {
		ret = security_context_to_sid(SUSFS_PRIV_APP_CONTEXT,
					      strlen(SUSFS_PRIV_APP_CONTEXT),
					      &susfs_priv_app_sid);
		if (ret)
			susfs_priv_app_sid = 0;
	}
}

bool susfs_is_current_ksu_domain(void)
{
	ensure_susfs_sids();
	return is_ksu_domain();
}

int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,
			void *envp, int *flags)
{
	struct user_arg_ptr *argv_ptr = argv;
	struct user_arg_ptr *envp_ptr = envp;

	ensure_susfs_sids();
	return ksu_handle_execveat_ksud(fd, filename_ptr, argv_ptr, envp_ptr,
					flags);
}

int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,
				void *argv, void *envp, int *flags)
{
	return ksu_handle_execveat(fd, filename_ptr, argv, envp, flags);
}

void ksu_handle_vfs_fstat(int fd, loff_t *kstat_size_ptr)
{
	struct file *file;

	if (!kstat_size_ptr)
		return;

	file = fget(fd);
	if (!file)
		return;

	if (is_init_rc_path(file))
		*kstat_size_ptr += ksu_rc_len;

	fput(file);
}

EXPORT_SYMBOL(ksu_handle_execveat);
EXPORT_SYMBOL(ksu_handle_execveat_sucompat);
EXPORT_SYMBOL(ksu_handle_vfs_fstat);
EXPORT_SYMBOL(susfs_is_current_ksu_domain);
EXPORT_SYMBOL(susfs_ksu_sid);
EXPORT_SYMBOL(susfs_priv_app_sid);
