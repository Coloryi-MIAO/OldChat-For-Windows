# OldChat For Windows 7

Windows 7/8 compatibility branch for OldChat. This branch is intentionally maintained separately from the all-platform application's `main` branch and is built with Flutter 3.19.6 on a Windows x64 runner.

## Build

Push to `master` to run the Windows 7 x64 workflow, or start it manually from GitHub Actions. The workflow runs analysis and tests before producing `OldChatForAllPlatformwindowsx64.exe`.

This branch targets Windows 7/8. The main all-platform branch targets Windows 10/11 and newer. The updater must select the Windows 7/8 executable for a Windows 7/8 client and the Windows 10/11+ executable for the current main client.

## Notes

The branch keeps the original API, realtime messaging, caching, and media playback behavior where Flutter 3.19.6 supports it. Unsupported newer platform features should be disabled here instead of changing the all-platform branch.
