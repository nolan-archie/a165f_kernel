#!/bin/bash
OUTPUT="combined_patches.txt"
rm -f "$OUTPUT"

FILES=(
  "./security/selinux/selinuxfs.c.orig"
  "./security/selinux/hooks.c.orig"
  "./security/selinux/avc.c.orig"
  "./fs/open.c.rej"
  "./fs/namespace.c.orig"
  "./fs/open.c.orig"
  "./fs/exec.c.rej"
  "./fs/exec.c.orig"
  "./fs/read_write.c.orig"
  "./fs/namei.c.orig"
  "./fs/proc/task_mmu.c.orig"
  "./fs/proc/base.c.orig"
  "./fs/proc/base.c.rej"
  "./fs/namespace.c.rej"
  "./kernel/sys.c.orig"
  "./kernel/reboot.c.orig"
  "./kernel/kallsyms.c.orig"
  "./mm/memory.c.orig"
)

for file in "${FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "=== FILE: $file ===" >> "$OUTPUT"
    cat "$file" >> "$OUTPUT"
    echo -e "\n\n" >> "$OUTPUT"
  fi
done
