# BetterBoard

An iOS keyboard that looks like Apple's, with Gboard-style **hold for symbols**:
each letter shows a small symbol in its corner — hold the key and release to type it.

Built entirely without a Mac: GitHub Actions builds an unsigned `.ipa`, which is
installed with [Sideloadly](https://sideloadly.io) using a free Apple ID.

## Install
1. Push to `main` (or run the **Build** workflow manually). Wait for it to finish (~5 min).
2. Download the `.ipa`:
   ```powershell
   ./scripts/get-ipa.ps1
   ```
3. Open Sideloadly, plug in the iPhone, drag in `build/BetterBoard.ipa`, sign in with your Apple ID, Start.
4. On the iPhone: **Settings › General › VPN & Device Management** → trust your Apple ID.
   (First time only: also turn on **Settings › Privacy & Security › Developer Mode**.)
5. Open the BetterBoard app and follow the setup steps.

With a free Apple ID the app stops working after 7 days — just reinstall with Sideloadly.

See [PLAN.md](PLAN.md) for the design decisions.
