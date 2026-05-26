# Quando o assignee de uma conversa é trocado, remove automaticamente o agente
# anterior da lista de participantes (se ele havia se adicionado).
# Isso evita que um agente continue vendo a conversa após ser substituído.
Rails.application.config.after_initialize do
  Conversation.class_eval do
    after_update :remove_previous_assignee_from_participants, if: :saved_change_to_assignee_id?

    private

    def remove_previous_assignee_from_participants
      previous_assignee_id = saved_change_to_assignee_id[0]
      return if previous_assignee_id.blank?

      ConversationParticipant.where(
        conversation_id: id,
        user_id: previous_assignee_id
      ).destroy_all
    end
  end
rescue => e
  Rails.logger.error "[RemovePrevAssignee] Falha ao aplicar patch: #{e.message}"
end
