# Third-party notices and scope

The project author's code and documentation are licensed under the root MIT LICENSE.
That license does not grant rights in third-party software, trademarks, interfaces, or artwork.

## Build and runtime dependencies

- The application links to macOS system frameworks (Cocoa, CoreGraphics, QuartzCore, and Foundation) and uses platform headers. These remain subject to Apple's applicable terms; this repository does not relicense them.
- The app invokes a separately installed Codex executable. Codex is not bundled or relicensed by this project.
- CI uses GitHub's actions/checkout at a pinned revision. This external action is not copied into the app and retains its upstream license.

A review of the current tracked source tree found no vendored third-party code, package lockfiles, or bundled image/font assets. This is a repository inspection result, not proof of the provenance of every line of code.

## Screenshots and names

README screenshots are linked GitHub user attachments, not application bundle resources. They can include third-party interfaces or a desktop pet. Their original ownership and any permission to reuse depicted artwork have not been independently verified. Do not assume the software's MIT license grants rights to those third-party elements.

OpenAI, Codex, ChatGPT, Apple, macOS, and GitHub names are used to describe compatibility or services. They remain the property of their respective owners. No affiliation, endorsement, or trademark license is implied.

Before publishing or reusing screenshots elsewhere, verify the image owner's rights and any applicable third-party permissions. Preserve original notices for any third-party material added later.
