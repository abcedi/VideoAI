# Security Policy

VideoAI processes local files and can acquire media from public URLs. Security issues may therefore involve filesystem handling, URL parsing, redirects, HTTP sessions, browser automation, subprocesses, temporary files, downloads, archives, and provenance.

## Supported version

| Version | Security support |
|---|---|
| `0.5.x` | Current |
| Earlier private TikTokAI versions | Not publicly supported |

## Reporting a vulnerability

Please **do not post exploit details, credentials, private URLs, cookies, tokens, or other sensitive material in a normal public issue**.

Preferred method:

1. Open the repository's **Security** tab.
2. Use **Report a vulnerability / Private vulnerability reporting** if available.

Repository: https://github.com/abcedi/VideoAI

If private vulnerability reporting is not available, open a minimal public issue saying you need a private channel for a security report. Do not include the vulnerability details.

## Useful report information

Where safe, include:

- VideoAI version;
- affected file/function;
- Windows/PowerShell/Python versions;
- reproduction steps;
- impact;
- affected input mode;
- whether arbitrary code execution or data exposure is possible;
- suggested remediation if known.

Redact private media and secrets.

## Secrets

Do not commit:

- passwords;
- API/access tokens;
- GitHub tokens;
- browser cookies;
- session IDs;
- signed CDN URLs;
- private repository/source URLs;
- personal browser profiles;
- real credential-bearing `.env` files.

`.gitignore` is not a security boundary. Always inspect staged changes.

## TikTok browser/session behavior

The current TikTok path uses an isolated Playwright browser context and does not import the user's normal logged-in browser cookie store.

The temporary browser context may create cookies required for the public media request. Those values should not be committed or intentionally persisted as source.

Changes that introduce profile reuse, persistent cookies, login state, or credentials are security-sensitive design changes.

## Signed media URLs

Public media services can produce temporary signed CDN URLs.

Do not commit them or paste them into public bug reports. Prefer stable public source URLs and non-sensitive provenance.

## Evidence package sensitivity

Generated packages can preserve whatever appeared or was spoken in the source, including personal information, credentials accidentally shown on screen, private messages, internal infrastructure, source code, filenames, or proprietary material.

Inspect packages before sharing them with an AI provider or another person.

## URL trust model

Treat supplied URLs as untrusted.

Future changes should carefully handle host validation, redirects, loopback/private-network access, file URLs, output filenames, and URL-to-command interpolation.

## Subprocess safety

Prefer argument arrays and explicit validation. Avoid constructing unsafe shell strings from untrusted input or exposing secrets in command-line arguments.

## Dependency security

Upstream vulnerabilities may affect VideoAI. Keep dependencies appropriately updated, but test upgrades because they can also change behavior.

## Release hygiene

Before releases:

- run a secret scanner;
- inspect `git diff --cached`;
- confirm no private/test media is present;
- confirm no personal filesystem paths are present;
- confirm no browser profile/cookie data is present;
- review third-party license changes.
