# Patch aplicado em config/initializers/account_dashboard_patch.rb
#
# Adiciona ao formulário de contas no Super Admin:
#   1) "Agentes veem todas as conversas" (toggle)
#   2) "Cor primária do tema" (color picker / campo hex)
#
# Ambos usam a coluna custom_attributes (JSONB) do Account — sem migrações.
#
# Chaves armazenadas:
#   account.custom_attributes['agent_see_all_conversations'] → Boolean
#   account.custom_attributes['theme_primary_color']         → String  "#rrggbb"

Rails.application.config.after_initialize do
  begin
    # ------------------------------------------------------------------
    # 1) Atributos virtuais no model Account
    # ------------------------------------------------------------------
    Account.class_eval do
      # --- toggle: agentes veem todas as conversas ---
      def agent_see_all_conversations
        (custom_attributes || {}).fetch('agent_see_all_conversations', false)
      end

      def agent_see_all_conversations=(value)
        self.custom_attributes = (custom_attributes || {}).merge(
          'agent_see_all_conversations' => ActiveModel::Type::Boolean.new.cast(value)
        )
      end

      # --- cor primária do tema ---
      def theme_primary_color
        (custom_attributes || {}).fetch('theme_primary_color', '')
      end

      def theme_primary_color=(value)
        # Aceita #rrggbb ou rrggbb (adiciona # automaticamente)
        raw = value.to_s.strip
        raw = "##{raw}" if raw.match?(/\A[0-9a-fA-F]{6}\z/)
        clean = raw.match?(/\A#[0-9a-fA-F]{6}\z/) ? raw : ''
        self.custom_attributes = (custom_attributes || {}).merge(
          'theme_primary_color' => clean
        )
      end
    end

    # ------------------------------------------------------------------
    # 2) Expor os campos no Administrate (Super Admin)
    # ------------------------------------------------------------------

    # 2a) Tipos dos campos
    original_types = AccountDashboard::ATTRIBUTE_TYPES.dup
    AccountDashboard.send(:remove_const, :ATTRIBUTE_TYPES)
    AccountDashboard.const_set(
      :ATTRIBUTE_TYPES,
      original_types.merge(
        agent_see_all_conversations: Administrate::Field::Boolean,
        theme_primary_color:         Administrate::Field::String
      ).freeze
    )

    # 2b) Página de edição (form)
    original_form = AccountDashboard::FORM_ATTRIBUTES.dup
    AccountDashboard.send(:remove_const, :FORM_ATTRIBUTES)
    AccountDashboard.const_set(
      :FORM_ATTRIBUTES,
      (original_form + [:agent_see_all_conversations, :theme_primary_color]).freeze
    )

    # 2c) Página de detalhes (show)
    original_show = AccountDashboard::SHOW_PAGE_ATTRIBUTES.dup
    AccountDashboard.send(:remove_const, :SHOW_PAGE_ATTRIBUTES)
    AccountDashboard.const_set(
      :SHOW_PAGE_ATTRIBUTES,
      (original_show + [:agent_see_all_conversations, :theme_primary_color]).freeze
    )

    # 2d) Strong params
    mod = Module.new do
      def permitted_attributes(action)
        super + [:agent_see_all_conversations, :theme_primary_color]
      end
    end
    AccountDashboard.prepend(mod)

    Rails.logger.info '[account_dashboard_patch] AccountDashboard patched com sucesso.'
  rescue StandardError => e
    Rails.logger.error "[account_dashboard_patch] Falha ao aplicar patch (app continua): #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n") rescue nil
  end
end
