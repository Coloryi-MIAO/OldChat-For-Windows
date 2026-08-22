# Plugin Development

Plugins use the host application's reviewed plugin API. A plugin must not read access tokens, execute arbitrary shell commands, or bypass host permissions.

## Package

Create an `.oldchat-plugin` package with a manifest, entry point, declared permissions, and localized display text. The host validates the manifest, asks for approval when required, and runs only enabled plugins.

## Runtime rules

- Keep network work asynchronous and bounded by timeouts.
- Use host callbacks for messages, notifications, and media.
- Treat incoming data as untrusted.
- Do not store credentials in plugin files.
- Use English fallback strings for every user-visible label.
- System scratch-card automation is disabled by default and must respect the user's configured schedule and limits.

## Compatibility

Test on Windows 7 with Flutter 3.19.6. Do not depend on APIs introduced after that Flutter version. Keep plugin behavior identical on the main branch unless the newer host explicitly adds a capability.
