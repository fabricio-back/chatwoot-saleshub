json.settings resource.settings
json.created_at resource.created_at
if resource.custom_attributes.present?
  json.custom_attributes do
    json.plan_name resource.custom_attributes['plan_name']
    json.subscribed_quantity resource.custom_attributes['subscribed_quantity']
    json.subscription_status resource.custom_attributes['subscription_status']
    json.subscription_ends_on resource.custom_attributes['subscription_ends_on']
    json.industry resource.custom_attributes['industry'] if resource.custom_attributes['industry'].present?
    json.company_size resource.custom_attributes['company_size'] if resource.custom_attributes['company_size'].present?
    json.timezone resource.custom_attributes['timezone'] if resource.custom_attributes['timezone'].present?
    json.logo resource.custom_attributes['logo'] if resource.custom_attributes['logo'].present?
    json.onboarding_step resource.custom_attributes['onboarding_step'] if resource.custom_attributes['onboarding_step'].present?
    json.marked_for_deletion_at resource.custom_attributes['marked_for_deletion_at'] if resource.custom_attributes['marked_for_deletion_at'].present?
    if resource.custom_attributes['marked_for_deletion_reason'].present?
      json.marked_for_deletion_reason resource.custom_attributes['marked_for_deletion_reason']
    end
    json.theme_primary_color resource.custom_attributes['theme_primary_color'] if resource.custom_attributes['theme_primary_color'].present?
  end
end
# Exposto fora do bloco custom_attributes para garantir presença mesmo quando
# custom_attributes está vazio ou nil (hash vazio é blank? == true no Rails)
json.agent_see_all_conversations((resource.custom_attributes || {})['agent_see_all_conversations'] == true)
json.domain resource.domain
json.features resource.enabled_features
json.id resource.id
json.locale resource.locale
json.name resource.name
json.support_email resource.support_email
json.status resource.status
json.cache_keys resource.cache_keys
