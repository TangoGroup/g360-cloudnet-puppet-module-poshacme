require 'json'
require 'time'

Facter.add(:poshacme_certs) do
  confine kernel: 'windows'

  setcode do
    begin
      command = <<~POWERSHELL
        powershell -NoProfile -NonInteractive -Command "Try {
          Get-ChildItem -Path Cert:\\LocalMachine\\My |
            Where-Object { $_.Subject -match 'CN=' } |
            ForEach-Object {
              if ($_.Subject -match 'CN=([^,]+)') {
                [PSCustomObject]@{
                  cn         = $Matches[1]
                  thumbprint = $_.Thumbprint
                  not_after  = $_.NotAfter.ToUniversalTime().ToString('o')
                }
              }
            } |
            ConvertTo-Json -Compress
        } Catch { '{}' }"
      POWERSHELL

      raw = Facter::Core::Execution.exec(command)
      parsed = raw && !raw.strip.empty? ? JSON.parse(raw) : []
      certs = parsed.is_a?(Array) ? parsed : [parsed]

      newest_by_cn = {}
      certs.each do |cert|
        cn = cert['cn']
        next if cn.nil? || cn.empty?

        not_after = Time.parse(cert['not_after'])
        current = newest_by_cn[cn]
        if current.nil? || not_after > current[:not_after]
          newest_by_cn[cn] = {
            thumbprint: cert['thumbprint'],
            not_after: not_after,
          }
        end
      rescue StandardError
        next
      end

      newest_by_cn.transform_values { |cert| cert[:thumbprint] }
    rescue StandardError
      {}
    end
  end
end
