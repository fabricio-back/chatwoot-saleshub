class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'
    return conversations if agent_see_all?

    accessible_conversations
  end

  private

  def accessible_conversations
    # Use subqueries (select, not pluck) to avoid loading IDs into Ruby memory
    participant_conv_ids = ConversationParticipant
      .where(user_id: user.id)
      .select(:conversation_id)

    scope = conversations.where(inbox: user.inboxes.where(account_id: account.id))

    scope.where(assignee_id: user.id)
         .or(scope.where(id: participant_conv_ids))
  end

  def account_user
    @account_user ||= AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end

  def agent_see_all?
    account.custom_attributes.fetch('agent_see_all_conversations', false) == true
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
