# g360-cloudnet-puppet-module-poshacme

Puppet module for managing Posh-ACME certificates on Windows nodes.

This module is intentionally application-agnostic. It installs Posh-ACME,
manages an HTTP-01 challenge webroot, requests/renews certificates, and installs
them into the Windows certificate store. Consuming profiles own application
bindings such as IIS or Apache.

## Usage

```puppet
class { 'poshacme':
  letsencrypt_email   => 'infrastructure-alerts@example.com',
  letsencrypt_domains => ['www.example.com'],
  cert_lineage        => 'www-example-com',
  webroot             => 'C:/inetpub/wwwroot',
  cert_store          => 'MY',
}
```

## Parameters

- `letsencrypt_email`: Email address for Let's Encrypt registration.
- `letsencrypt_domains`: Domains included on the certificate. The first domain is treated as the primary name.
- `cert_lineage`: Posh-ACME order name.
- `webroot`: Webroot path used for HTTP-01 challenges.
- `cert_store`: Windows certificate store used for checks and cleanup. Defaults to `MY`.
- `force_renew`: Skips the Puppet expiry guard. Defaults to `false`.
- `manage_cleanup`: Removes matching certs expired more than 90 days. Defaults to `true`.

## Renewal Behavior

The certificate request exec is guarded by certificate expiry. It skips when the
primary certificate has more than 30 days remaining, and runs when no cert exists
or the cert is inside the 30-day renewal window.

`New-PACertificate` is not run with `-Force`, so Posh-ACME's own renewal logic
also prevents needless duplicate issuance.

## Facts

The module ships `poshacme_certs`, a Windows-only fact returning a hash of
certificate CN to newest thumbprint:

```puppet
$thumbprint = $facts['poshacme_certs']['www.example.com']
```

When more than one certificate exists for the same CN, the fact returns the
thumbprint for the cert with the latest `NotAfter` date.

## Two-Pass Binding

Facts are resolved before catalog application. On a zero-cert node, the first
Puppet run requests and installs the certificate. The next Puppet run sees the
new thumbprint in `poshacme_certs`, allowing the consuming profile to bind it to
the application.

This module does not manage IIS bindings directly.
