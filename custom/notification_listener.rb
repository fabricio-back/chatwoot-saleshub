# v1.12 — NotificationListener: conversation_created notifica apenas administradores.
# Agentes comuns só são notificados via conversation_assignment quando a conversa
# for atribuída a eles, evitando acesso a conversas não atribuídas pelo sino 🔔.
class NotificationListener < BaseListener
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event, 'conversation')
    agent_see_all = (account.custom_attributes || {})['agent_see_all_conversations'] == true

    # Notifica administradores sempre; notifica agentes se a conta permite visibilidade total
    recipients = agent_see_all ? account.users : account.users.joins(:account_users).where(account_users: { role: :administrator })

    recipients.each do |user|
      NotificationBuilder.new(
        notification_type: 'conversation_creation',
        user: user,
        conversation: conversation
      ).perform
    end
  end
end

NotificationListener.prepend_mod_with('NotificationListener')
