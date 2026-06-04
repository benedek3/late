# Late

Late is a lightweight native macOS menu bar AI workspace.

## Run

```sh
swift run
```

The app runs as a menu bar accessory with no Dock icon and opens a centered floating workspace window.

## Setup

On first launch, Late asks for an OpenRouter API key and stores it in macOS Keychain under `dev.late.openrouter`.

After setup:

- Click `Late` in the macOS menu bar to open the workspace.
- Press `Option+Tab` to toggle it globally.
- Press `Escape` to hide the workspace.
- Press `Command+B` to show or hide history.
- Press `Command+T` to start a new chat.
- Use `Settings` to update the OpenRouter key or change the appearance shortcut.
- Toggle `Web` in the prompt bar to enable OpenRouter web search for the next request. Web answers are instructed to include sources, and returned source annotations are shown as clickable links under the response.
- Start a new chat without deleting the current one.
- Saved chat metadata is encrypted on device at `~/Library/Application Support/Late/chats.index.enc.json`, and each chat thread is encrypted separately under `~/Library/Application Support/Late/chats/`.
- Pick a model from the selector at the top of the panel.
- Send prompts with `Command+Return`.

All model requests go through OpenRouter at `https://openrouter.ai/api/v1/chat/completions`.
