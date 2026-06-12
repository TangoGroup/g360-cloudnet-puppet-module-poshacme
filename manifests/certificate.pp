# Request and renew a single Posh-ACME certificate on Windows.
#
# Declare one instance per certificate. The request and cleanup scripts run
# inline via the PowerShell provider (no scripts are written to disk), so
# multiple certificates can coexist on the same node without resource
# collisions. Consuming profiles own application bindings such as IIS or Apache.
#
# @param letsencrypt_email Email address for Let's Encrypt certificate registration.
# @param letsencrypt_domains Domains to include on the ACME certificate. The first domain is the primary certificate name.
# @param cert_lineage Name used for the Posh-ACME order. Defaults to the resource title.
# @param webroot Webroot path used for ACME HTTP-01 challenges.
# @param cert_store Windows certificate store to use for certificate checks and cleanup.
# @param force_renew Whether to skip the Puppet expiry guard and run the request script.
# @param manage_cleanup Whether to manage cleanup of stale certificates matching the requested domains.
define poshacme::certificate (
  String $letsencrypt_email,
  Array[String] $letsencrypt_domains = [],
  String $cert_lineage = $title,
  String $webroot = 'C:/inetpub/wwwroot',
  String $cert_store = 'MY',
  Boolean $force_renew = false,
  Boolean $manage_cleanup = true,
) {
  if empty($letsencrypt_domains) {
    fail('poshacme::certificate requires at least one domain in letsencrypt_domains')
  }

  include poshacme

  $primary_domain = $letsencrypt_domains[0]
  $letsencrypt_hosts = join($letsencrypt_domains, ',')

  $request_unless = join([
      "\$escapedDomain = [regex]::Escape('${primary_domain}')",
      "\$cert = Get-ChildItem Cert:\\LocalMachine\\${cert_store} |",
      '  Where-Object { $_.Subject -match "CN=$escapedDomain(?:,|$)" } |',
      '  Sort-Object NotAfter -Descending |',
      '  Select-Object -First 1',
      'if ($cert -and $cert.NotAfter -gt (Get-Date).AddDays(30)) { exit 0 } else { exit 1 }',
  ], "\n")

  $cleanup_onlyif = join(concat(
      [
        '$domains = @(',
      ],
      $letsencrypt_domains.map |$domain| {
        "  '${domain}',"
      },
      [
        ')',
        '$cutoff = (Get-Date).AddDays(-90)',
        "\$certs = Get-ChildItem Cert:\\LocalMachine\\${cert_store}",
        'foreach ($cert in $certs) {',
        '  if ($cert.NotAfter -ge $cutoff) { continue }',
        '  foreach ($domain in $domains) {',
        '    $escapedDomain = [regex]::Escape($domain)',
        '    if ($cert.Subject -match "CN=$escapedDomain(?:,|$)") { exit 0 }',
        '    foreach ($extension in $cert.Extensions) {',
        '      if (',
        '        $null -ne $extension.Oid -and',
        '        $extension.Oid.FriendlyName -eq "Subject Alternative Name" -and',
        '        $extension.Format($false) -match "(^|,\s*)DNS Name=$escapedDomain(,|$)"',
        '      ) { exit 0 }',
        '    }',
        '  }',
        '}',
        'exit 1',
      ],
  ), "\n")

  $webroot_config_content = @(END)
    <?xml version="1.0" encoding="UTF-8"?>
    <configuration>
        <system.webServer>
            <staticContent>
                <mimeMap fileExtension="." mimeType="text/plain" />
            </staticContent>
        </system.webServer>
    </configuration>
    | END

  # Multiple certificates may share a webroot, so dedupe these with
  # ensure_resource. Puppet's file autorequire handles parent-dir ordering.
  ensure_resource('file', $webroot, { 'ensure' => 'directory' })
  ensure_resource('file', "${webroot}/.well-known", { 'ensure' => 'directory' })
  ensure_resource('file', "${webroot}/.well-known/acme-challenge", { 'ensure' => 'directory' })
  ensure_resource('file', "${webroot}/.well-known/acme-challenge/web.config", {
      'ensure'  => 'file',
      'content' => $webroot_config_content,
  })

  $request_command = epp('poshacme/request-poshacme-certificate.ps1.epp', {
      'letsencrypt_hosts' => $letsencrypt_hosts,
      'webroot'           => $webroot,
      'cert_lineage'      => $cert_lineage,
      'cert_store'        => $cert_store,
      'letsencrypt_email' => $letsencrypt_email,
  })

  $request_require = [
    Class['poshacme'],
    File["${webroot}/.well-known/acme-challenge"],
    File["${webroot}/.well-known/acme-challenge/web.config"],
  ]

  # When force_renew is set, drop the expiry guard so the request always runs.
  $request_guard = $force_renew ? {
    true    => undef,
    default => $request_unless,
  }

  exec { "request-poshacme-certificate-${title}":
    command   => $request_command,
    provider  => powershell,
    unless    => $request_guard,
    logoutput => true,
    timeout   => 1200,
    require   => $request_require,
  }

  if $manage_cleanup {
    $cleanup_command = epp('poshacme/cleanup-poshacme-certs.ps1.epp', {
        'letsencrypt_hosts' => $letsencrypt_hosts,
        'cert_lineage'      => $cert_lineage,
        'cert_store'        => $cert_store,
    })

    exec { "cleanup-poshacme-certs-${title}":
      command   => $cleanup_command,
      provider  => powershell,
      logoutput => true,
      onlyif    => $cleanup_onlyif,
      require   => Exec["request-poshacme-certificate-${title}"],
    }
  }
}
