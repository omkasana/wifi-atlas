# Contributing to WiFi Atlas

Small fixes, useful features, documentation, and reproducible bug reports are welcome. This is a source-available project under a [custom license](LICENSE), not MIT. Private noncommercial changes are free. Commercial use/distribution is automatically licensed while compliant with the 25% royalty on gross attributable revenue and quarterly reporting/payment within 30 days. Written approval is not required. General noncommercial redistribution remains restricted apart from GitHub/platform and contribution exceptions. See the [licensing guide](docs/LICENSING.md).

## Get started

Fork <https://github.com/omkasana/wifi-atlas>, then clone your fork:

```sh
git clone https://github.com/YOUR-USERNAME/wifi-atlas.git
cd wifi-atlas
git remote add upstream https://github.com/omkasana/wifi-atlas.git
git switch -c feature/describe-your-change
./scripts/build.sh
open "dist/WiFi Atlas.app"
```

Use an Apple silicon Mac with macOS 14+, compatible Swift/Command Line Tools, and Python 3. Full Xcode is needed for XCTest and the system-widget build; local package builds do not need a signing account. Read the [source map](docs/ARCHITECTURE.md) before moving responsibilities between modules.

## Making changes

- Keep native macOS controls, simple labels, keyboard access, VoiceOver alternatives, and Reduce Motion behavior.
- Preserve the difference between signal strength, interface traffic, Wi-Fi link rate, and measured internet throughput.
- Keep scans and throughput tests explicit. Avoid new idle polling loops, unbounded buffers, private APIs, or privileged helpers.
- Add meaningful checks for new measurement logic, persistence/migrations, cancellation, or failure handling. Use deterministic fake data/transports; normal test runs must not consume internet-test bandwidth.
- Preserve old archives and historical survey geometry. Do not silently rewrite an unsupported archive version.
- If you add/remove an app source or change generated project settings, update the generator and run `python3 scripts/generate-xcode-project.py`.
- Update relevant usage/architecture/release docs. Keep focused changes separate from unrelated cleanup.

## Verify and submit

```sh
./scripts/test-standalone.sh
./scripts/build.sh
# With full Xcode selected:
./scripts/test.sh

git diff --check
git add <files-you-changed>
git commit -m "Describe the resulting change"
git push -u origin feature/describe-your-change
```

Open a pull request against `main`. Describe the problem, resulting behavior, relevant checks, and any unverified hardware/UI paths. Add screenshots for visible changes using a fictional network/layout. CI artifacts are development builds, not notarized releases.

Before publishing diagnostics, remove SSIDs, IP/MAC addresses, location/floor-plan details, usernames, tokens, and signing information. Do not attach live archives or credentials.

## Keep your fork current

Commit or stash your local work first:

```sh
git fetch upstream
git switch main
git merge --ff-only upstream/main
git push origin main
git switch -c feature/next-change
```

If your branch has diverged, review and reconcile the commits rather than forcing an update over your work.

## Incoming contribution terms

You retain copyright in your original contributions. By intentionally submitting a contribution to this repository, you grant Om Kasana a perpetual, worldwide, nonexclusive, royalty-free, irrevocable copyright license to use, reproduce, modify, create derivatives of, publicly display, distribute, and sublicense your contribution as part of WiFi Atlas or derivatives under its current or future licensing terms, including commercial terms. This allows the maintainer to develop and license the combined project without owing you a royalty merely for accepting your contribution. This is not a transfer of your copyright or a promise of compensation or revenue sharing.

Submit only work you have authority to license on these terms. Identify any third-party material and its license; do not include incompatible code, private information, or material requiring another person's permission without that permission. Mark material you do not intend as a contribution clearly and obtain agreement before submitting it. Confirm these terms in the pull-request checklist.

## Reports and conduct

Use issue templates for bugs and feature ideas. Include macOS/app versions, reproduction steps, expected/actual behavior, and whether the issue involves package or Xcode/widget builds. Respectful, specific discussion is expected; do not post harassment or other people’s private information. Report security-sensitive issues through [SECURITY.md](SECURITY.md), not a public bug report.
