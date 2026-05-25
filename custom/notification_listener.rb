# v1.12 — NotificationListener: conversation_created notifica apenas administradores.
# Agentes comuns só são notificados via conversation_assignment quando a conversa
# for atribuída a eles, evitando acesso a conversas não atribuídas pelo sino 🔔.
#
# IMPORTANTE: usa prepend para sobrescrever APENAS conversation_created,
# preservando assignee_changed, message_created e conversation_bot_handoff originais.
Rails.application.config.after_initialize do
  mod = Module.new do
    def conversation_created(event)
      conversation, account = extract_conversation_and_account(event, 'conversation')
      return if conversation.pending?

      agent_see_all = (account.custom_attributes || {})['agent_see_all_conversations'] == true

      # Notifica administradores sempre; notifica agentes se a conta permite visibilidade total
      recipients = if agent_see_all
        account.users
      else
        account.users.joins(:account_users).where(account_users: { role: :administrator })
      end

      recipients.each do |user|
        NotificationBuilder.new(
          notification_type: 'conversation_creation',
          user: user,
          account: account,
          primary_actor: conversation
        ).perform
      end
    end
  end

  NotificationListener.prepend(mod)
  Rails.logger.info '[NotificationListener] Patch conversation_created aplicado com sucesso.'
rescue => e
  Rails.logger.error "[NotificationListener] Falha ao aplicar patch: #{e.message}"
end
