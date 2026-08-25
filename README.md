<p align="center">
  <img src="Assets/icon.png" width="140" alt="GitSwitch icon">
</p>

<h1 align="center">GitSwitch</h1>

A macOS menu bar app for switching between multiple GitHub accounts on one Mac.

The menu bar always shows the active account. Switching does two things in one click:

- runs `gh auth switch`, so `git push` (over HTTPS via the `gh auth git-credential` helper) uses the selected account
- syncs the global git `user.name` / `user.email` to that account's commit identity, so commits are attributed correctly

## Features

- One-click account switching from the menu bar
- Add any number of GitHub accounts via GitHub's device login flow (the app shows the one-time code, copies it to the clipboard, and opens the browser)
- Manage window: edit each account's commit name/email, fetch them from the GitHub profile, sign accounts out
- Optional launch at login
- No Electron, no dependencies — a single small SwiftUI binary that drives the `gh` CLI

## Requirements

- macOS 13+
- [GitHub CLI](https://cli.github.com) (`brew install gh`)
- Xcode command line tools (to build)

## Build & install

```sh
./build.sh install
```

Builds `build/GitSwitch.app` and copies it to `~/Applications`, then launches it.

## How it works

The account list and active account are read from gh's `~/.config/gh/hosts.yml`. Switching runs `gh auth switch --hostname github.com --user <login>`. Per-account commit identities are stored in the app's `UserDefaults` (`com.pratikaman.gitswitch`) and written to the global git config on switch. Repos with a local `user.email` override, and repos using SSH remotes, are unaffected by switching.
