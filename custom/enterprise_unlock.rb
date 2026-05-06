# Unlock enterprise-tier features in Super Admin
# Sets INSTALLATION_PRICING_PLAN to 'enterprise' so that:
#   - Custom Branding
#   - Agent Capacity
#   - Audit Logs
#   - Disable Branding
# ...are unlocked (no longer show the lock icon).
#
# SAML SSO remains locked — it requires the /app/enterprise directory
# (enterprise source code) which is not included in this image.

Rails.application.config.after_initialize do
  Thread.new do
    retries = 0
    begin
      ActiveRecord::Base.connection_pool.with_connection do
        config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
        # value_changed? retorna false para atributos virtuais (não é coluna DB),
        # então verificamos o valor atual antes de salvar.
        unless config.value.to_s == 'enterprise'
          config.value = 'enterprise'
          config.save!
        end
      end
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
      retries += 1
      sleep 3
      retry if retries < 5
    rescue StandardError => e
      Rails.logger.warn "[EnterpriseUnlock] #{e.message}"
    end
  end
end
