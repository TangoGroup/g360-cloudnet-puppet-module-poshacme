# Changelog

## 0.1.0 - 2026-06-12

- Initial module for Windows Posh-ACME certificate management.
- Add guarded certificate request flow to avoid repeated Let's Encrypt issuance.
- Add `poshacme_certs` fact for CN-to-thumbprint lookups.
- Add optional stale certificate cleanup for matching domains expired more than 90 days.
