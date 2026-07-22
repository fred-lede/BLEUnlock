# Traditional Chinese README and MIT License Design

## Goal

Add a complete Traditional Chinese guide for this BLEUnlock fork and make its MIT licensing and attribution explicit. The documentation must distinguish the upstream project from this fork without implying that upstream releases contain the fork's added features.

## Scope

This documentation task will:

- add `README_CHT.md` as a complete Traditional Chinese counterpart to the current `README.md`;
- add a Traditional Chinese language link to `README.md`;
- add a root `LICENSE` file containing the complete MIT License text;
- preserve upstream attribution to Takeshi Sone and identify `fred-lede` as the copyright holder for the fork's 2026 modifications; and
- document the fork's existing code and Xcode-project changes accurately.

This task will not make further changes to application source code or Xcode settings. That statement describes only the scope of this documentation task; the README will clearly state that the fork already contains program and Xcode-project modifications.

## README_CHT.md Structure

The Traditional Chinese README will translate the current English README completely, including:

- overview, features, requirements, installation, and initial setup;
- device naming behaviour;
- Telegram notifications, photo capture, and Mac location attachment;
- options and troubleshooting;
- BLE MAC-address limitations;
- event-script compatibility;
- source-build output paths;
- funding, credits, and licensing.

The beginning of the document will include a prominent fork notice that:

- links to the upstream `ts1/BLEUnlock` repository;
- names Takeshi Sone as the original author;
- names `fred-lede` as the fork maintainer;
- lists the fork's notable additions, including Traditional Chinese localization, Telegram notifications with optional photos and location, improved Apple-device naming and scan behaviour, camera warm-up, and stable proximity confirmation; and
- explains that upstream Homebrew and release downloads may not contain these fork-specific additions.

For readers who want this fork's features, the document will direct them to build this repository from source unless this fork publishes its own release.

The upstream donation links will be retained but labelled as support links for the original author, so the fork does not impersonate the upstream maintainer.

## License and Attribution

The root `LICENSE` file will use the standard MIT License text and contain both notices:

```text
Copyright (c) 2019-2022 Takeshi Sone
Copyright (c) 2026 fred-lede
```

The original notice will not be removed or replaced. The second notice covers modifications made in this fork. The Traditional Chinese README's license section will link to `LICENSE`, identify the original author and fork maintainer, and state that the original code and fork modifications are distributed under the MIT License.

Third-party attribution already present in the README, including the Apache License 2.0 note for icons, will remain intact.

## Validation

Validation will confirm that:

- `README_CHT.md` covers every current top-level English README section;
- relative links and section anchors resolve to repository files or intended external pages;
- `README.md` links to the Traditional Chinese document;
- `LICENSE` contains the full standard MIT text and both copyright notices;
- no application source or Xcode-project files changed in this documentation task;
- Markdown contains no unfinished placeholders; and
- `git diff --check` reports no whitespace errors.

## Sources

- Upstream project: <https://github.com/ts1/BLEUnlock>
- Open Source Initiative MIT License: <https://opensource.org/license/mit>
- GitHub repository licensing guidance: <https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository>
