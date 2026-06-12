require 'json'
require 'base64'
require 'time'

Facter.add(:poshacme_certs) do
  confine kernel: 'windows'

  setcode do
    begin
      script = <<~POWERSHELL
        $results = @()
        Get-ChildItem -Path Cert:\\LocalMachine\\My | ForEach-Object {
          $cert = $_
          $names = @()
          if ($cert.Subject -match 'CN=([^,]+)') {
            $names += $Matches[1]
          }
          foreach ($extension in $cert.Extensions) {
            if ($null -ne $extension.Oid -and $extension.Oid.FriendlyName -eq 'Subject Alternative Name') {
              $names += [regex]::Matches($extension.Format($false), 'DNS Name=([^,]+)') |
                ForEach-Object { $_.Groups[1].Value }
            }
          }
          foreach ($name in ($names | Where-Object { $_ } | Select-Object -Unique)) {
            $results += [PSCustomObject]@{
              name       = $name
              thumbprint = $cert.Thumbprint
              not_after  = $cert.NotAfter.ToUniversalTime().ToString('o')
            }
          }
        }
        $results | ConvertTo-Json -Compress
      POWERSHELL
      encoded_script = Base64.strict_encode64(script.encode('UTF-16LE'))
      command = "powershell -NoProfile -NonInteractive -EncodedCommand #{encoded_script}"

      raw = Facter::Core::Execution.exec(command)
      parsed = raw && !raw.strip.empty? ? JSON.parse(raw) : []
      certs = parsed.is_a?(Array) ? parsed : [parsed]

      newest_by_name = {}
      certs.each do |cert|
        name = cert['name']
        next if name.nil? || name.empty?

        not_after = Time.parse(cert['not_after'])
        current = newest_by_name[name]
        if current.nil? || not_after > current[:not_after]
          newest_by_name[name] = {
            thumbprint: cert['thumbprint'],
            not_after: not_after,
          }
        end
      rescue StandardError
        next
      end

      newest_by_name.transform_values { |cert| cert[:thumbprint] }
    rescue StandardError
      {}
    end
  end
end
