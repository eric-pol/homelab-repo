#!/bin/bash

# --- CONFIGURATION ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
FILES_DIR="$REPO_ROOT/files"
TARGET_FSTAB="/etc/fstab"
TARGET_SMB_CONF="/etc/samba/smb.conf"

echo "--- 🚀 Start Deployment ---"

# 1. Update the Repo
echo "📥 1. Executing Git Pull..."
cd "$REPO_ROOT"
git pull origin main

# 2. VALIDATION
# 2-1. Validate fstab
echo "🔍 2. Starting fstab validation..."
if [ -f "$FILES_DIR$TARGET_FSTAB" ]; then
    if ! findmnt --verify --tab-file "$FILES_DIR$TARGET_FSTAB" > /dev/null 2>&1; then
        echo "❌ CRITICAL ERROR: The new fstab contains errors!"
        findmnt --verify --tab-file "$FILES_DIR$TARGET_FSTAB"
        exit 1
    else
        echo "   ✅ fstab is valid."
    fi
fi

# 2-2. Validate smb.conf
echo "🔍 3. Starting samba validation..."
if [ -f "$FILES_DIR$TARGET_SMB_CONF" ]; then
    if ! testparm -s "$FILES_DIR$TARGET_SMB_CONF" > /dev/null 2>&1; then
        echo "❌ CRITICAL ERROR: The new smb.conf contains errors!"
        exit 1
    else
        echo "   ✅ Samba config is valid."
    fi
fi

# 3. CAPTURE BEFORE STATES
# 3-1. CAPTURE BEFORE STATE of fstab (Before Sync)
# We calculate the 'fingerprint' (MD5 hash) of the current live file
# If the file doesn't exist yet, we set the hash to "none"
if [ -f "$TARGET_FSTAB" ]; then
    PRE_FSTAB_HASH=$(md5sum "$TARGET_FSTAB" | awk '{print $1}')
else
    PRE_FSTAB_HASH="none"
fi

# 3-2. CAPTURE BEFORE STATE of smb.conf (Before Sync)
# We calculate the 'fingerprint' (MD5 hash) of the current live file
# If the file doesn't exist yet, we set the hash to "none"
if [ -f "$TARGET_SMB_CONF" ]; then
    PRE_SMB_HASH=$(md5sum "$TARGET_SMB_CONF" | awk '{print $1}')
else
    PRE_SMB_HASH="none"
fi

# 4. SYNCHRONIZE
echo "🔄 4. Synchronizing files..."
sudo rsync -av --no-owner --no-group "$FILES_DIR/" /

# 5. CAPTURE AFTER STATES
# 5-1. CAPTURE AFTER STATE of fstab (After Sync)
if [ -f "$TARGET_FSTAB" ]; then
    POST_FSTAB_HASH=$(md5sum "$TARGET_FSTAB" | awk '{print $1}')
else
    POST_FSTAB_HASH="none"
fi

# 5-2. CAPTURE AFTER STATE of smb.conf (After Sync)
if [ -f "$TARGET_SMB_CONF" ]; then
    POST_SMB_HASH=$(md5sum "$TARGET_SMB_CONF" | awk '{print $1}')
else
    POST_SMB_HASH="none"
fi

# 6. CHECK CHANGES AND RELOAD & RESTART
echo "⚡ 5. Checking for changes..."

# 6-2. Compare the two fstab fingerprints - if different restart
if [ "$PRE_FSTAB_HASH" != "$POST_FSTAB_HASH" ]; then
    echo "   ⚠  Configuration changed! Reloading systemd configs & Mounting filesystems..."
    sudo systemctl daemon-reload
    sudo mount -a
    echo "   ✅ Filesystems mounted."
else
    echo "   ☕ No changes in fstab. Skipping mounting."
fi

# 6-2. Compare the two smb fingerprints - if different restart Samba (smbd & nmbd (netbios names))
if [ "$PRE_SMB_HASH" != "$POST_SMB_HASH" ]; then
    echo "   ⚠️  Configuration changed! Restarting Samba..."
    sudo systemctl restart smbd
    sudo systemctl restart nmbd
    echo "   ✅ Services restarted."
else
    echo "   ☕ No changes in Samba configuration. Skipping restart."
fi

echo "--- 🎉 Done! ---"
