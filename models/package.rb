class Package < Sequel::Model
  DEFAULT_CATEGORY = 'general'.freeze
  plugin :timestamps, update_on_create: true

  def self.all_as_json
    {
      packages: self.all.map(&:to_package_json)
    }.to_json
  end

  def self.resources_zip
    io = Zip::OutputStream.write_buffer do |zos|
      self.each do |pkg|
        zos.put_next_entry(File.join(pkg.identifier, 'icon.png'))
        zos.write(pkg.icon_data)
      end

      # Required as KiCad PCM expects at least one file
      if self.empty?
        zos.put_next_entry(File.join('empty_repository'))
        zos.write('')
      end
    end
    io.rewind

    io
  end

  def to_package_json
    data = JSON.parse(self.metadata_json)
    data['versions'][0].merge!({
                                'download_sha256' => self.sha256,
                                'download_size' => self.size,
                                'install_size' => self.install_size,
                                'download_url' => File.join(BASE_URL, 'packages', id.to_s, 'download.zip')
                              })
    data
  end
end