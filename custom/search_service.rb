# v1.14 — SearchService: mantém interface original do Chatwoot (pattr_initialize + params hash)
# + aplica filtro de permissões para agentes (assignee ou participante).
# Corrige busca de conversas por nome do contato via JOIN.
class SearchService
  pattr_initialize [:current_user!, :current_account!, :params!, :search_type!]

  def account_user
    @account_user ||= current_account.account_users.find_by(user: current_user)
  end

  def perform
    case search_type
    when 'Message'
      { messages: filter_messages }
    when 'Conversation'
      { conversations: filter_conversations }
    when 'Contact'
      { contacts: filter_contacts }
    when 'Article'
      { articles: filter_articles }
    else
      {
        contacts: filter_contacts,
        messages: filter_messages,
        conversations: filter_conversations,
        articles: filter_articles
      }
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def search_query
    @search_query ||= params[:q].to_s.strip
  end

  def accessable_inbox_ids
    @accessable_inbox_ids ||= current_user.assigned_inboxes.select(:id)
  end

  def agent_see_all?
    (current_account.custom_attributes || {})['agent_see_all_conversations'] == true
  end

  def filter_conversations
    query = current_account.conversations
                           .joins('INNER JOIN contacts ON conversations.contact_id = contacts.id')
                           .where(
                             'cast(conversations.display_id as text) ILIKE :search
                              OR contacts.name ILIKE :search
                              OR contacts.email ILIKE :search
                              OR contacts.phone_number ILIKE :search
                              OR contacts.identifier ILIKE :search',
                             search: "%#{search_query}%"
                           )

    unless administrator? || agent_see_all?
      query = query.where(inbox_id: accessable_inbox_ids)
      query = query.where(
        'conversations.assignee_id = :uid OR conversations.id IN (SELECT conversation_id FROM conversation_participants WHERE user_id = :uid)',
        uid: current_user.id
      )
    end

    @conversations = query.order('conversations.created_at DESC')
                          .page(params[:page])
                          .per(15)
  end

  def filter_messages
    query = current_account.messages
                           .where('messages.created_at >= ?', 3.months.ago)
                           .where('messages.content ILIKE :search', search: "%#{search_query}%")

    unless administrator? || agent_see_all?
      query = query.where(inbox_id: accessable_inbox_ids)
      query = query.where(
        'messages.conversation_id IN (
          SELECT id FROM conversations
          WHERE assignee_id = :uid OR id IN (SELECT conversation_id FROM conversation_participants WHERE user_id = :uid)
        )',
        uid: current_user.id
      )
    end

    @messages = query.reorder('messages.created_at DESC')
                     .page(params[:page])
                     .per(15)
  end

  def filter_contacts
    @contacts = current_account.contacts
                               .where(
                                 'name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q OR identifier ILIKE :q',
                                 q: "%#{search_query}%"
                               )
                               .order(last_activity_at: :desc)
                               .page(params[:page])
                               .per(15)
  end

  def filter_articles
    @articles = current_account.articles
                               .text_search(search_query)
                               .page(params[:page])
                               .per(15)
  end
end

SearchService.prepend_mod_with('SearchService')
