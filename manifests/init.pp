# Manage node-level Posh-ACME setup on Windows.
#
# This class installs the Posh-ACME PowerShell module and manages the shared
# working directory used for logs. It is intentionally application-agnostic and
# holds no per-site state; declare one `poshacme::certificate` resource per
# certificate you need on the node.
class poshacme {
  $install_unless = join([
      'if (',
      '  (Get-Module -ListAvailable -Name Posh-ACME) -or',
      '  (Test-Path "C:/Program Files/WindowsPowerShell/Modules/Posh-ACME")',
      ') { exit 0 } else { exit 1 }',
  ], "\n")

  file { 'poshacme-temp':
    ensure => directory,
    path   => 'C:/temp',
  }

  exec { 'install_poshacme_module':
    command   => '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (-not (Get-Module -ListAvailable -Name Posh-ACME)) { if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force } ; if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { Register-PSRepository -Name PSGallery -SourceLocation https://www.powershellgallery.com/api/v2 -InstallationPolicy Trusted } else { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted } ; Install-Module -Name Posh-ACME -Scope AllUsers -Force -AllowClobber -Confirm:$false }',
    provider  => powershell,
    unless    => $install_unless,
    logoutput => true,
    timeout   => 1200,
  }
}
