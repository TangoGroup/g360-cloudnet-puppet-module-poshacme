# Changelog

## 0.2.0 - 2026-06-12

- Split into a node-level `poshacme` class (Posh-ACME install + working dir) and a per-site `poshacme::certificate` defined type, enabling multiple certificates on a single node.
- Run the request and cleanup PowerShell inline via the PowerShell provider; no `.ps1` files are written to disk, removing fixed-path collisions.
- Namespace debug logs per certificate (`C:/temp/poshacme-{request,cleanup}-<cert_lineage>.log`).

## 0.1.0 - 2026-06-12

- Initial module for Windows Posh-ACME certificate management.
- Add guarded certificate request flow to avoid repeated Let's Encrypt issuance.
- Add `poshacme_certs` fact for CN-to-thumbprint lookups.
- Add optional stale certificate cleanup for matching domains expired more than 90 days.
