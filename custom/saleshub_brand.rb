# SalesHub brand initializer — runs after Rails boots
# Sets logo paths in InstallationConfig if they still point to default SVG files
Rails.application.config.after_initialize do
  Thread.new do
    retries = 0
    begin
      ActiveRecord::Base.connection_pool.with_connection do
        {
          'LOGO' => '/brand-assets/logo.png',
          'LOGO_THUMBNAIL' => '/brand-assets/logo_thumbnail.png',
          'LOGO_DARK' => '/brand-assets/logo.png',
        }.each do |key, png_path|
          config = InstallationConfig.find_by(name: key)
          next unless config
          config.update!(value: png_path) if config.value.to_s.end_with?('.svg')
        end
      end
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
      retries += 1
      sleep 3
      retry if retries < 5
    rescue StandardError => e
      Rails.logger.warn "[SalesHub] brand initializer error: #{e.message}"
    end
  end
end
