# Manage Posh-ACME certificate issuance on Windows.
#
# This module is intentionally application-agnostic. It requests and renews
# certificates into the local Windows certificate store; consuming profiles own
# application bindings such as IIS or Apache.
#
# @param letsencrypt_email Email address for Let's Encrypt certificate registration.
# @param letsencrypt_domains Domains to include on the ACME certificate. The first domain is the primary certificate name.
# @param cert_lineage Name used for the Posh-ACME order.
# @param webroot Webroot path used for ACME HTTP-01 challenges.
# @param cert_store Windows certificate store to use for certificate checks and cleanup.
# @param force_renew Whether to skip the Puppet expiry guard and run the request script.
# @param manage_cleanup Whether to manage cleanup of stale certificates matching the requested domains.
class poshacme (
  String $letsencrypt_email,
  Array[String] $letsencrypt_domains = [],
  String $cert_lineage = 'poshacme',
  String $webroot = 'C:/inetpub/wwwroot',
  String $cert_store = 'MY',
  Boolean $force_renew = false,
  Boolean $manage_cleanup = true,
) {
  if empty($letsencrypt_domains) {
    fail('poshacme requires at least one domain in letsencrypt_domains')
  }

  $primary_domain = $letsencrypt_domains[0]
  $letsencrypt_hosts = join($letsencrypt_domains, ',')
  $powershell_path = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

  $request_unless = join([
      "\$escapedDomain = [regex]::Escape('${primary_domain}')",
      "\$cert = Get-ChildItem Cert:\\LocalMachine\\${cert_store} |",
      '  Where-Object { $_.Subject -match "CN=$escapedDomain(?:,|$)" } |',
      '  Sort-Object NotAfter -Descending |',
      '  Select-Object -First 1',
      'if ($cert -and $cert.NotAfter -gt (Get-Date).AddDays(30)) { exit 0 } else { exit 1 }',
  ], "\n")
  $install_unless = join([
      'if (',
      '  (Get-Module -ListAvailable -Name Posh-ACME) -or',
      '  (Test-Path "C:/Program Files/WindowsPowerShell/Modules/Posh-ACME")',
      ') { exit 0 } else { exit 1 }',
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

  file { $webroot:
    ensure => directory,
  }

  file { "${webroot}/.well-known":
    ensure  => directory,
    require => File[$webroot],
  }

  file { "${webroot}/.well-known/acme-challenge":
    ensure  => directory,
    require => File["${webroot}/.well-known"],
  }

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

  file { "${webroot}/.well-known/acme-challenge/web.config":
    ensure  => file,
    content => $webroot_config_content,
    require => File["${webroot}/.well-known/acme-challenge"],
  }

  file { 'poshacme-temp':
    ensure => directory,
    path   => 'C:/temp',
  }

  file { 'C:/temp/request-poshacme-certificate.ps1':
    ensure  => file,
    content => epp('poshacme/request-poshacme-certificate.ps1.epp', {
        'letsencrypt_hosts' => $letsencrypt_hosts,
        'webroot'           => $webroot,
        'cert_lineage'      => $cert_lineage,
        'cert_store'        => $cert_store,
        'letsencrypt_email' => $letsencrypt_email,
    }),
    require => File['poshacme-temp'],
  }

  exec { 'install_poshacme_module':
    command   => '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (-not (Get-Module -ListAvailable -Name Posh-ACME)) { if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force } ; if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { Register-PSRepository -Name PSGallery -SourceLocation https://www.powershellgallery.com/api/v2 -InstallationPolicy Trusted } else { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted } ; Install-Module -Name Posh-ACME -Scope AllUsers -Force -AllowClobber -Confirm:$false }',
    provider  => powershell,
    unless    => $install_unless,
    logoutput => true,
    timeout   => 1200,
  }

  $request_command = @("POWERSHELL"/L)
    & '${powershell_path}' `
      -NoProfile `
      -NonInteractive `
      -ExecutionPolicy Bypass `
      -File C:/temp/request-poshacme-certificate.ps1
    | POWERSHELL
  $request_require = [
    Exec['install_poshacme_module'],
    File['C:/temp/request-poshacme-certificate.ps1'],
    File["${webroot}/.well-known/acme-challenge"],
    File["${webroot}/.well-known/acme-challenge/web.config"],
  ]

  if $force_renew {
    exec { 'request-poshacme-certificate':
      command   => $request_command,
      provider  => powershell,
      logoutput => true,
      timeout   => 1200,
      require   => $request_require,
    }
  } else {
    exec { 'request-poshacme-certificate':
      command   => $request_command,
      provider  => powershell,
      unless    => $request_unless,
      logoutput => true,
      timeout   => 1200,
      require   => $request_require,
    }
  }

  if $manage_cleanup {
    file { 'C:/temp/cleanup-poshacme-certs.ps1':
      ensure  => file,
      content => epp('poshacme/cleanup-poshacme-certs.ps1.epp', {
          'letsencrypt_hosts' => $letsencrypt_hosts,
          'cert_store'        => $cert_store,
      }),
      require => File['poshacme-temp'],
    }

    $cleanup_command = @("POWERSHELL"/L)
      & '${powershell_path}' `
        -NoProfile `
        -NonInteractive `
        -ExecutionPolicy Bypass `
        -File C:/temp/cleanup-poshacme-certs.ps1
      | POWERSHELL

    exec { 'cleanup-poshacme-certs':
      command   => $cleanup_command,
      provider  => powershell,
      logoutput => true,
      onlyif    => $cleanup_onlyif,
      require   => [
        File['C:/temp/cleanup-poshacme-certs.ps1'],
        Exec['request-poshacme-certificate'],
      ],
    }
  }
}
