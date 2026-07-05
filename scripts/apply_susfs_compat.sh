#!/usr/bin/env bash
set -euo pipefail

cd "${GITHUB_WORKSPACE:-$(pwd)}"

python3 - <<'PY'
from pathlib import Path
import re

def replace_if_present(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    if new in s:
        return
    if old not in s:
        return
    p.write_text(s.replace(old, new, 1))

def insert_before_marker(path: str, marker: str, insert: str) -> None:
    p = Path(path)
    s = p.read_text()
    if insert in s:
        return
    if marker not in s:
        raise SystemExit(f"marker not found in {path}: {marker!r}")
    p.write_text(s.replace(marker, insert + "\n" + marker, 1))

# kallsyms: use the inline helper header, not a fake extern
replace_if_present(
    "kernel-5.10/kernel/kallsyms.c",
    "#ifdef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS\nextern bool susfs_starts_with(const char *str, const char *prefix);\n#endif",
    "#ifdef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS\n#include <linux/susfs_def.h>\n#endif",
)

# fs/susfs.c: add compatibility wrappers for the newer API names
p = Path("kernel-5.10/fs/susfs.c")
s = p.read_text()

kstat_wrapper = """
void susfs_sus_kstat_spoof_generic_fillattr(struct inode *inode, struct kstat *stat)
{
\tif (!inode)
\t\treturn;

\tsusfs_sus_ino_for_generic_fillattr(inode->i_ino, stat);
}

void susfs_sus_kstat_spoof_show_map_vma(struct inode *inode, dev_t *out_dev, unsigned long *out_ino)
{
\tif (!inode)
\t\treturn;

\tsusfs_sus_ino_for_show_map_vma(inode->i_ino, out_dev, out_ino);
}
"""

redirect_wrapper = """
struct filename *susfs_open_redirect_spoof_do_sys_openat(struct inode *inode)
{
\tif (!inode)
\t\treturn ERR_PTR(-ENOENT);

\treturn susfs_get_redirected_path(inode->i_ino);
}
"""

if "susfs_sus_kstat_spoof_generic_fillattr" not in s:
    marker = "#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT"
    s = s.replace(marker, kstat_wrapper + "\n" + marker, 1)

if "susfs_open_redirect_spoof_do_sys_openat" not in s:
    marker = "#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT"
    s = s.replace(marker, redirect_wrapper + "\n" + marker, 1)

p.write_text(s)

# include/linux/susfs.h: declare the wrapper APIs
h = Path("kernel-5.10/include/linux/susfs.h")
hs = h.read_text()

if "susfs_sus_kstat_spoof_generic_fillattr" not in hs:
    hs = hs.replace(
        "void susfs_sus_ino_for_generic_fillattr(unsigned long ino, struct kstat *stat);\n",
        "void susfs_sus_ino_for_generic_fillattr(unsigned long ino, struct kstat *stat);\nvoid susfs_sus_kstat_spoof_generic_fillattr(struct inode *inode, struct kstat *stat);\n",
        1,
    )

if "susfs_sus_kstat_spoof_show_map_vma" not in hs:
    hs = hs.replace(
        "void susfs_sus_ino_for_show_map_vma(unsigned long ino, dev_t *out_dev, unsigned long *out_ino);\n",
        "void susfs_sus_ino_for_show_map_vma(unsigned long ino, dev_t *out_dev, unsigned long *out_ino);\nvoid susfs_sus_kstat_spoof_show_map_vma(struct inode *inode, dev_t *out_dev, unsigned long *out_ino);\n",
        1,
    )

if "susfs_open_redirect_spoof_do_sys_openat" not in hs:
    hs = hs.replace(
        "struct filename* susfs_get_redirected_path(unsigned long ino);\n",
        "struct filename* susfs_get_redirected_path(unsigned long ino);\nstruct filename *susfs_open_redirect_spoof_do_sys_openat(struct inode *inode);\n",
        1,
    )

h.write_text(hs)

# source call sites: keep them aligned with the wrapper names
replace_if_present(
    "kernel-5.10/fs/stat.c",
    "extern void susfs_sus_ino_for_generic_fillattr(unsigned long ino, struct kstat *stat);",
    "extern void susfs_sus_kstat_spoof_generic_fillattr(struct inode *inode, struct kstat *stat);",
)
replace_if_present(
    "kernel-5.10/fs/stat.c",
    "susfs_sus_ino_for_generic_fillattr(inode->i_ino, stat);",
    "susfs_sus_kstat_spoof_generic_fillattr(inode, stat);",
)

replace_if_present(
    "kernel-5.10/fs/proc/task_mmu.c",
    "extern void susfs_sus_ino_for_show_map_vma(unsigned long ino, dev_t *out_dev, unsigned long *out_ino);",
    "extern void susfs_sus_kstat_spoof_show_map_vma(struct inode *inode, dev_t *out_dev, unsigned long *out_ino);",
)
replace_if_present(
    "kernel-5.10/fs/proc/task_mmu.c",
    "susfs_sus_ino_for_show_map_vma(inode->i_ino, &dev, &ino);",
    "susfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);",
)

replace_if_present(
    "kernel-5.10/fs/namei.c",
    "extern struct filename* susfs_get_redirected_path(unsigned long ino);",
    "extern struct filename *susfs_open_redirect_spoof_do_sys_openat(struct inode *inode);",
)
replace_if_present(
    "kernel-5.10/fs/namei.c",
    "fake_pathname = susfs_get_redirected_path(filp->f_inode->i_ino);",
    "fake_pathname = susfs_open_redirect_spoof_do_sys_openat(filp->f_inode);",
)
PY

grep -R "susfs_open_redirect_spoof_do_sys_openat\|susfs_sus_kstat_spoof_show_map_vma\|susfs_sus_kstat_spoof_generic_fillattr" kernel-5.10 -n

python3 - <<'PY'
from pathlib import Path
import re

wf = Path(".github/workflows/weekly-build.yml")
s = wf.read_text()

start = "      - name: Apply SUSFS compatibility shims"
end = "      - name: Write version defconfig"

if start in s and end in s:
    s = re.sub(
        rf"{re.escape(start)}.*?{re.escape(end)}",
        "      - name: Apply SUSFS compatibility shims\n        run: bash scripts/apply_susfs_compat.sh\n\n" + end,
        s,
        flags=re.S,
    )
else:
    raise SystemExit("could not find the malformed workflow block to replace")

wf.write_text(s)
print("workflow fixed")
PY

chmod +x scripts/apply_susfs_compat.sh

git add .github/workflows/weekly-build.yml scripts/apply_susfs_compat.sh
git commit -m "ci: fix SUSFS compatibility workflow" || true
git diff -- .github/workflows/weekly-build.yml scripts/apply_susfs_compat.sh
cd ~/a165f_kernel

cat > scripts/apply_susfs_compat.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "${GITHUB_WORKSPACE:-$(pwd)}"

python3 - <<'PY'
from pathlib import Path
import re

def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    if new in s:
        return
    if old not in s:
        raise SystemExit(f"missing marker in {path}: {old!r}")
    p.write_text(s.replace(old, new, 1))

def insert_before(path: str, marker: str, text: str) -> None:
    p = Path(path)
    s = p.read_text()
    if text in s:
        return
    if marker not in s:
        raise SystemExit(f"marker not found in {path}: {marker!r}")
    p.write_text(s.replace(marker, text + "\n" + marker, 1))

# kallsyms: use the inline helper header
replace_once(
    "kernel-5.10/kernel/kallsyms.c",
    "#ifdef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS\nextern bool susfs_starts_with(const char *str, const char *prefix);\n#endif",
    "#ifdef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS\n#include <linux/susfs_def.h>\n#endif",
)

# Restore setuid_hook call if it was removed
replace_once(
    "KernelSU/kernel/setuid_hook.c",
    "    susfs_set_current_proc_umounted();\n\n    return 0;\n}",
    "#ifdef CONFIG_KSU_SUSFS_SUS_PATH\n    susfs_run_sus_path_loop(new_uid);\n#endif // #ifdef CONFIG_KSU_SUSFS_SUS_PATH\n\n    susfs_set_current_proc_umounted();\n\n    return 0;\n}",
)

# Compatibility wrappers for older SUSFS API
p = Path("kernel-5.10/fs/susfs.c")
s = p.read_text()

if "susfs_sus_kstat_spoof_generic_fillattr" not in s:
    s = s.replace(
        "#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT",
        """void susfs_sus_kstat_spoof_generic_fillattr(struct inode *inode, struct kstat *stat)
{
\tif (!inode)
\t\treturn;

\tsusfs_sus_ino_for_generic_fillattr(inode->i_ino, stat);
}

void susfs_sus_kstat_spoof_show_map_vma(struct inode *inode, dev_t *out_dev, unsigned long *out_ino)
{
\tif (!inode)
\t\treturn;

\tsusfs_sus_ino_for_show_map_vma(inode->i_ino, out_dev, out_ino);
}

#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT""",
        1,
    )

if "susfs_open_redirect_spoof_do_sys_openat" not in s:
    s = s.replace(
        "#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT",
        """struct filename *susfs_open_redirect_spoof_do_sys_openat(struct inode *inode)
{
\tif (!inode)
\t\treturn ERR_PTR(-ENOENT);

\treturn susfs_get_redirected_path(inode->i_ino);
}

#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT""",
        1,
    )

p.write_text(s)

# Add prototypes
h = Path("kernel-5.10/include/linux/susfs.h")
hs = h.read_text()

if "susfs_sus_kstat_spoof_generic_fillattr" not in hs:
    hs = hs.replace(
        "void susfs_sus_ino_for_generic_fillattr(unsigned long ino, struct kstat *stat);\n",
        "void susfs_sus_ino_for_generic_fillattr(unsigned long ino, struct kstat *stat);\nvoid susfs_sus_kstat_spoof_generic_fillattr(struct inode *inode, struct kstat *stat);\n",
        1,
    )

if "susfs_sus_kstat_spoof_show_map_vma" not in hs:
    hs = hs.replace(
        "void susfs_sus_ino_for_show_map_vma(unsigned long ino, dev_t *out_dev, unsigned long *out_ino);\n",
        "void susfs_sus_ino_for_show_map_vma(unsigned long ino, dev_t *out_dev, unsigned long *out_ino);\nvoid susfs_sus_kstat_spoof_show_map_vma(struct inode *inode, dev_t *out_dev, unsigned long *out_ino);\n",
        1,
    )

if "susfs_open_redirect_spoof_do_sys_openat" not in hs:
    hs = hs.replace(
        "struct filename* susfs_get_redirected_path(unsigned long ino);\n",
        "struct filename* susfs_get_redirected_path(unsigned long ino);\nstruct filename *susfs_open_redirect_spoof_do_sys_openat(struct inode *inode);\n",
        1,
    )

h.write_text(hs)

# Call-site compatibility for current tree
replace_once(
    "kernel-5.10/fs/stat.c",
    "extern void susfs_sus_ino_for_generic_fillattr(unsigned long ino, struct kstat *stat);",
    "extern void susfs_sus_kstat_spoof_generic_fillattr(struct inode *inode, struct kstat *stat);",
)
replace_once(
    "kernel-5.10/fs/stat.c",
    "susfs_sus_ino_for_generic_fillattr(inode->i_ino, stat);",
    "susfs_sus_kstat_spoof_generic_fillattr(inode, stat);",
)

replace_once(
    "kernel-5.10/fs/proc/task_mmu.c",
    "extern void susfs_sus_ino_for_show_map_vma(unsigned long ino, dev_t *out_dev, unsigned long *out_ino);",
    "extern void susfs_sus_kstat_spoof_show_map_vma(struct inode *inode, dev_t *out_dev, unsigned long *out_ino);",
)
replace_once(
    "kernel-5.10/fs/proc/task_mmu.c",
    "susfs_sus_ino_for_show_map_vma(inode->i_ino, &dev, &ino);",
    "susfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);",
)

replace_once(
    "kernel-5.10/fs/namei.c",
    "extern struct filename* susfs_get_redirected_path(unsigned long ino);",
    "extern struct filename *susfs_open_redirect_spoof_do_sys_openat(struct inode *inode);",
)
replace_once(
    "kernel-5.10/fs/namei.c",
    "fake_pathname = susfs_get_redirected_path(filp->f_inode->i_ino);",
    "fake_pathname = susfs_open_redirect_spoof_do_sys_openat(filp->f_inode);",
)
PY

grep -R "susfs_open_redirect_spoof_do_sys_openat\|susfs_sus_kstat_spoof_show_map_vma\|susfs_sus_kstat_spoof_generic_fillattr" kernel-5.10 KernelSU -n
