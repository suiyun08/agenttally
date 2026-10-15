---
name: cctop-setup
description: Use when cctop-hook command fails or is not found. Guides user to install the cctop menubar app.
---

# cctop Setup Skill

Helps install the cctop app required for session monitoring.

## When to Use

**Run installation guidance when:**
- Hook fails with "cctop-hook not found"
- User asks to set up cctop monitoring
- Session tracking is not working

## Installation

### Step 1: Check if AgentTally.app is installed

```bash
ls /Applications/AgentTally.app/Contents/MacOS/cctop-hook 2>/dev/null || ls ~/Applications/AgentTally.app/Contents/MacOS/cctop-hook 2>/dev/null
```

If not found, the user needs to install AgentTally.app.

### Step 2: Install AgentTally

Download the latest DMG from https://github.com/suiyun08/agenttally/releases/latest
(`AgentTally-macOS-arm64.dmg` for Apple Silicon, `AgentTally-macOS-x86_64.dmg` for Intel) and
drag `AgentTally.app` into `/Applications/`.

The build is not notarized by Apple, so macOS blocks its first launch. The user can allow it in
System Settings › Privacy & Security › Open Anyway, or run:

```bash
xattr -dr com.apple.quarantine /Applications/AgentTally.app
```

### Step 3: Verify installation

```bash
/Applications/AgentTally.app/Contents/MacOS/cctop-hook --version
```

### Step 4: Launch the app

```bash
open /Applications/AgentTally.app
```

## After Installation

The hooks registered by this plugin will now work. Session data will be written to `~/.cctop/sessions/` when Claude Code or Claude Desktop hooks fire.

The menubar app will show session status in the macOS menu bar.
