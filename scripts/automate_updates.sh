#!/bin/bash

# Configuration
SUKISU_UPSTREAM="https://github.com/SukiSU-Ultra/SukiSU-Ultra.git"
SUSFS_UPSTREAM="https://gitlab.com/simonpunk/susfs4ksu.git"
SUPERCALL_FILE="KernelSU/kernel/supercall/supercall.c"
BRIDGE_FILE="KernelSU/kernel/susfs_bridge.c"

echo "Starting automated updates for KernelSU and SUSFS..."

# 1. Fetch Changelogs
echo "Fetching changelogs..."
git clone --depth 50 $SUKISU_UPSTREAM upstream_sukisu
git clone --depth 50 $SUSFS_UPSTREAM upstream_susfs

echo "## SukiSU-Ultra Updates" > changelog.md
git -C upstream_sukisu log --since="1 week ago" --oneline >> changelog.md
echo "" >> changelog.md
echo "## SUSFS Updates" >> changelog.md
git -C upstream_susfs log --since="1 week ago" --oneline >> changelog.md

# 2. Update KernelSU directory
echo "Updating KernelSU source..."
if [ -f "$BRIDGE_FILE" ]; then
    echo "Backing up custom bridge..."
    cp "$BRIDGE_FILE" /tmp/susfs_bridge.c.bak
fi

# Sync from upstream
# We use rsync to mirror the upstream but keep our .git if we are in the main repo
rsync -a --exclude=.git upstream_sukisu/ KernelSU/

# Restore custom bridge
if [ -f "/tmp/susfs_bridge.c.bak" ]; then
    echo "Restoring custom bridge..."
    cp /tmp/susfs_bridge.c.bak "$BRIDGE_FILE"
fi

# 3. Patch supercall.c
echo "Checking supercall.c for SUSFS integration..."

# Ensure include is present
if ! grep -q "linux/susfs.h" "$SUPERCALL_FILE"; then
    echo "Adding <linux/susfs.h> include..."
    sed -i '/#include "uapi\/supercall.h"/i #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs.h>\n#endif' "$SUPERCALL_FILE"
fi

# Ensure dispatch logic is present
if grep -q "CONFIG_KSU_SUSFS" "$SUPERCALL_FILE" && grep -q "CMD_SUSFS_ADD_SUS_PATH" "$SUPERCALL_FILE"; then
    echo "SUSFS logic already present in supercall.c"
else
    echo "Patching supercall.c with SUSFS logic..."
    # Define the block to insert
    # We use a temporary file to avoid complex escaping in sed
    cat <<EOF > /tmp/susfs_block.txt
#ifdef CONFIG_KSU_SUSFS
	if (magic1 == KSU_INSTALL_MAGIC1 && magic2 == SUSFS_MAGIC) {
		switch (cmd) {
		case CMD_SUSFS_ADD_SUS_PATH:
			return susfs_add_sus_path(arg);
		case CMD_SUSFS_ADD_HIDE_DET_PATH:
			return susfs_add_hide_det_path(arg);
		case CMD_SUSFS_ADD_OPEN_REDIRECT:
			return susfs_add_open_redirect(arg);
		case CMD_SUSFS_ENABLE_SUSFS:
			return susfs_enable_susfs(arg);
		case CMD_SUSFS_SET_UNAME:
			return susfs_set_uname(arg);
		case CMD_SUSFS_SHOW_SUSFS_STATUS:
			return susfs_show_susfs_status(arg);
		case CMD_SUSFS_SHOW_VERSION:
			susfs_show_version(arg);
			return 0;
		default:
			return -1;
		}
	}
#endif
EOF
    # Insert before the KSU_INSTALL_MAGIC2 check
    # Find the line number of KSU_INSTALL_MAGIC2 check
    LINE_NUM=$(grep -n "magic1 == KSU_INSTALL_MAGIC1 && magic2 == KSU_INSTALL_MAGIC2" "$SUPERCALL_FILE" | head -n 1 | cut -d: -f1)
    if [ ! -z "$LINE_NUM" ]; then
        { head -n $((LINE_NUM - 1)) "$SUPERCALL_FILE"; cat /tmp/susfs_block.txt; tail -n +$LINE_NUM "$SUPERCALL_FILE"; } > /tmp/temp.c
        mv /tmp/temp.c "$SUPERCALL_FILE"
        echo "Successfully patched supercall.c before line $LINE_NUM"
    else
        echo "ERROR: Could not find KSU_INSTALL_MAGIC2 check in supercall.c"
        exit 1
    fi
fi

# 4. Update SUSFS files if needed
# (Optional: sync files from upstream_susfs/kernel/ into the kernel tree)
# For now, we assume the kernel already has SUSFS integrated and we just update the bridge/KSU part.

# 5. Clean up
rm -rf upstream_sukisu upstream_susfs /tmp/susfs_block.txt /tmp/susfs_bridge.c.bak

echo "Updates and patching completed successfully."
