# Security patch: restrict agents from viewing all conversations of a contact.
#
# Gap coberto: endpoint GET /api/v1/accounts/:id/contacts/:contact_id/conversations
# — sem este patch, qualquer agente que abre o perfil de um contato vê TODAS as
#   conversas daquele contato, incluindo as atribuídas a outros agentes.
#
# Regras:
#   - Administrador → vê tudo
#   - Agente         → vê apenas conversas onde é o assignee ou participante
#   - Toggle agent_see_all_conversations → IGNORADO (travado em false para esta conta)
#
# Aplica patch em: Api::V1::Accounts::Contacts::ConversationsController#index
# via Module#prepend para não depender do código-fonte da versão upstream.

Rails.application.config.after_initialize do
  module Contacts
    module ConversationsPermissionPatch
      # Chamado após o `index` original setar @conversations.
      # Como Jbuilder renderiza de forma lazy (após o método retornar),
      # filtrar @conversations aqui é suficiente.
      def index
        super
        return unless @conversations.respond_to?(:where)

        account_user = Current.account&.account_users&.find_by(user_id: Current.user&.id)

        # Administradores veem tudo
        return if account_user&.administrator?

        # Agentes: filtrar por assignee ou participante
        uid = Current.user&.id
        return unless uid

        participant_subquery = ConversationParticipant
          .where(user_id: uid)
          .select(:conversation_id)

        mine         = @conversations.where(assignee_id: uid)
        participating = @conversations.where(id: participant_subquery)

        @conversations = mine.or(participating)
      end
    end
  end

  begin
    Api::V1::Accounts::Contacts::ConversationsController
      .prepend(Contacts::ConversationsPermissionPatch)
    Rails.logger.info '[ContactConversationsFilter] Patch aplicado com sucesso.'
  rescue NameError => e
    Rails.logger.warn "[ContactConversationsFilter] Patch não aplicado: #{e.message}"
  end
end
