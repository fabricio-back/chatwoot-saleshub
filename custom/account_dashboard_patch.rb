# Adds agent_see_all_conversations toggle to Account via custom_attributes.
# Exposes it in the Administrate Super Admin dashboard as a checkbox.
#
# HOW IT WORKS (no migration needed):
#   Account has a jsonb column `custom_attributes`.
#   We store the flag there and surface it as a virtual attribute.
#
# USAGE in initializers (loaded once, safe to fail on cold boot):
#   Account.include(AccountDashboardPatch)
#
# Super Admin dashboard: config/initializers/administrate.rb (or equivalent)
# adds :agent_see_all_conversations to the fields list.

module AccountDashboardPatch
  extend ActiveSupport::Concern

  included do
    # Virtual attribute backed by custom_attributes jsonb column
    def agent_see_all_conversations
      custom_attributes.fetch('agent_see_all_conversations', false) == true
    end

    def agent_see_all_conversations=(value)
      self.custom_attributes = custom_attributes.merge(
        'agent_see_all_conversations' => ActiveModel::Type::Boolean.new.cast(value)
      )
    end
  end
end

# Patch Account model and expose in Administrate -------------------------
begin
  Account.include(AccountDashboardPatch) unless Account.ancestors.include?(AccountDashboardPatch)

  # Administrate dashboard patch — add field if dashboard class is loaded
  if defined?(Admin::AccountDashboard)
    Admin::AccountDashboard.class_eval do
      ATTRIBUTE_TYPES['agent_see_all_conversations'] ||=
        Administrate::Field::Boolean

      SHOW_PAGE_ATTRIBUTES   |= ['agent_see_all_conversations']
      FORM_PAGE_ATTRIBUTES   |= ['agent_see_all_conversations']
    end
  end
rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad => e
  Rails.logger.warn("[account_dashboard_patch] DB not ready yet: #{e.message} — will retry on next request")
rescue StandardError => e
  Rails.logger.warn("[account_dashboard_patch] #{e.class}: #{e.message}")
end
