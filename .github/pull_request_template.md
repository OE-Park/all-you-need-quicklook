## Summary

<!-- What changed, and why? -->

## Validation

<!-- Design/docs: inspection performed; build optional. Implementation: relevant tests + host build (or CI link). Rendering: live WKWebView assertions and Finder + Space checks. List unrun/manual checks separately. -->

## Security

- [ ] Untrusted text/attributes/script data use destination-appropriate escaping; intentional raw HTML remains subject to CSP/navigation restrictions.
- [ ] Only app-controlled scripts receive the document nonce, where nonce support is implemented.
- [ ] No new network, entitlement, or CSP hole.
- [ ] No secrets in the diff.

## Checklist

- [ ] Matches the current plan task file list.
- [ ] Tests updated when Shared behavior changed.
- [ ] `*.xcodeproj` is not in the commit.
