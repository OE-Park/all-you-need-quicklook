# Security Policy

## Supported Versions

This project is under active development. Security fixes go to the latest commit on `main`.

## Reporting a Vulnerability

Do not put suspected vulnerability details in a public issue, discussion, or pull request.

1. Use [private vulnerability reporting](https://github.com/OE-Park/all-you-need-quicklook/security/advisories/new).
2. If that is unavailable, contact [@OE-Park](https://github.com/OE-Park) through a private channel.
3. Otherwise open a public issue that only says you have a security report and need a private channel. Do not describe the issue.

Include:

- description and potential impact
- affected file, component, or commit
- reproduction steps or a minimal proof of concept
- suggested mitigation, if known

Do not include real user files, App Group data, or secrets. Use synthetic content.

The maintainer acknowledges reports within 3 business days and gives an initial assessment within 7 business days. Confirmed issues are fixed on a private branch and disclosed after a fix is available.

## Scope

Useful reports include:

- XSS via rendered Markdown, logs, or notebook HTML
- WKWebView navigation or script injection outside bundled JS
- App Group config tampering
- sandbox or entitlement bypass
- leaked secrets in the repo or CI logs

Third-party library issues that are not caused by this repo's configuration should go to the vendor.
