# Remove DashboardApps e scripts indesejados do BD.
# - Kanban externo (astraonline)
# - Apps legados do fazer-ai que não são usados (Conexões, Chats Internos, Projetos, Chatbot Flows, Config Extra)
Rails.application.config.after_initialize do
  Thread.new do
    retries = 0
    begin
      removed = 0

      if defined?(DashboardApp)
        unwanted_names = [
          'kanban', 'Conexões', 'Conexoes', 'Chats Internos',
          'Projetos', 'Chatbot Flows', 'Config Extra'
        ]

        # Usa binds parametrizados — evita string interpolation em SQL
        # DashboardApp usa a coluna 'title' (não 'name')
        name_binds = unwanted_names.map { |n| "%#{DashboardApp.sanitize_sql_like(n)}%" }
        name_placeholders = unwanted_names.map { 'title ILIKE ?' }.join(' OR ')
        apps_to_remove = DashboardApp.where(
          "(#{name_placeholders}) OR content::text ~* 'kanban|moveisback\\.com\\.br'",
          *name_binds
        )

        count = apps_to_remove.destroy_all.size
        removed += count
        Rails.logger.info "[CleanApps] DashboardApps removidos: #{count}" if count > 0
      end

      if defined?(InstallationConfig)
        all_configs = InstallationConfig.where("name LIKE '%script%' OR name LIKE '%dashboard%'")
        all_configs.each do |cfg|
          next unless cfg.value.to_s =~ /kanban|moveisback\.com\.br/i
          cfg.update!(value: '')
          removed += 1
          Rails.logger.info "[CleanApps] InstallationConfig '#{cfg.name}' limpo"
        end
      end

      Rails.logger.info "[CleanApps] Limpeza concluída. Total removido/limpo: #{removed}"
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
      retries += 1
      sleep 5
      retry if retries < 6
    rescue => e
      Rails.logger.warn "[CleanApps] Erro na limpeza: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end
  end
end
