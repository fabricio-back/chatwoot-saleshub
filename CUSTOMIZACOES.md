# Guia de Customizações — Chatwoot SalesHub

Este documento descreve todas as customizações aplicadas neste projeto e como alterá-las para um novo cliente.

---

## 1. Identidade Visual (Branding)

### Tema de cores
**Arquivo:** `custom/theme-colors.js`

Altere o valor hex para a cor principal do cliente:
```js
// Linha ~92
woot: {
  ...
  500: '#23c93e',  // ← cor principal (botões, destaques)
},
n: {
  brand: '#23c93e',  // ← mesma cor
}
```

### Logo e favicon
**Pasta:** `brand-assets/`

Substitua os arquivos mantendo os mesmos nomes:
- `brand-assets/logo.png` — logo clara (fundo escuro)
- `brand-assets/logo-dark.png` — logo escura (fundo claro)
- `brand-assets/favicon.ico` — favicon do browser

O inicializador `custom/saleshub_brand.rb` aplica os logos automaticamente no banco ao iniciar.

### "Powered by" na tela de login
**Arquivo:** `custom/LoginIndex.vue`

```vue
<!-- Procure por "verticegrowth" e troque a URL e o texto -->
<a href="https://verticegrowth.com" target="_blank">verticegrowth.com</a>
```

---

## 2. Permissões de Acesso dos Agentes

### O que agentes veem na lista de conversas

**Arquivo:** `custom/permission_filter_service.rb`

Comportamento atual: agentes veem conversas onde são **responsável (assignee)** OU **participante**.

Para restringir apenas ao assignee (comportamento padrão do Chatwoot):
```ruby
def accessible_conversations
  conversations
    .where(inbox: user.inboxes.where(account_id: account.id))
    .where(assignee_id: user.id)
end
```

Para liberar tudo (agentes veem todas as conversas das suas inboxes):
```ruby
def accessible_conversations
  conversations.where(inbox: user.inboxes.where(account_id: account.id))
end
```

### Aba "Minhas" — quem aparece

**Arquivo:** `custom/conversation_finder.rb` — método `mine_conversations`

Comportamento atual: assignee + participantes.

Para voltar ao padrão (só assignee):
```ruby
def mine_conversations(base = @conversations)
  base.assigned_to(current_user)
end
```

### Abas "Todas" e "Não atribuídas"

**Arquivo:** `custom/Sidebar.vue`

As abas são removidas do array `menuItems` para agentes. Administradores veem tudo normalmente. Para reativar, adicionar de volta os itens no array.

---

## 3. Participantes como Co-responsáveis

Quando um agente é adicionado como **participante** de uma conversa (painel direito → "Participantes"), ele:
- Vê a conversa na aba "Minhas"
- Tem acesso à conversa mesmo não sendo o assignee

Para desativar esse comportamento, altere `permission_filter_service.rb` e `conversation_finder.rb` conforme seção 2 acima.

---

## 4. Kanban

### Serviços
- `kanban-backend` — API Node.js (porta 3001 local / porta 3000 interna)
- `kanban-frontend` — Interface React via Nginx (porta 3002 local)

### Como funciona
O `kanban-backend` injeta um script JS na tabela `installation_configs.DASHBOARD_SCRIPTS` do Postgres do Chatwoot. Esse script aparece automaticamente no sidebar do Chatwoot para todos os usuários.

### Variáveis importantes
| Variável | Descrição |
|---|---|
| `KANBANCW_DOMAIN` | URL pública do kanban-backend (ex: `https://kanban-api.cliente.com`) |
| `CHATWOOT_DOMAIN` | URL pública do Chatwoot |
| `CHATWOOT_API_URL` | URL **interna** do Chatwoot (`http://rails:3000`) — não alterar |
| `CORS_ORIGIN` | URL do Chatwoot (para CORS) |

### Para desativar o Kanban
Remova os serviços `kanban-backend` e `kanban-frontend` do `docker-compose.coolify.yml`.

---

## 5. Deploy no Coolify

### Variáveis obrigatórias no Coolify
| Variável | Exemplo |
|---|---|
| `FRONTEND_URL` | `https://chat.cliente.com` |
| `KANBAN_BACKEND_URL` | `https://kanban-api.cliente.com` |
| `MAILER_SENDER_EMAIL` | `noreply@cliente.com` |
| `RESEND_API_KEY` | chave da Resend (para emails) |
| `BRAND_ASSETS_URL` | URL de um .zip com os brand-assets (opcional) |

### Processo de deploy
1. Fork ou clone este repositório para o novo cliente
2. Altere os arquivos de customização conforme necessário
3. Faça o build da imagem: `docker build -f Dockerfile.full -t ghcr.io/SEU_USUARIO/chatwoot-CLIENTE:latest .`
4. Faça push: `docker push ghcr.io/SEU_USUARIO/chatwoot-CLIENTE:latest`
5. No Coolify: crie um novo serviço usando o `docker-compose.coolify.yml` como base
6. Configure todas as variáveis de ambiente
7. Crie domínios para `rails` (porta 3000), `kanban-backend` (porta 3000) e `kanban-frontend` (porta 80)

---

## 6. Resumo dos Arquivos Customizados

| Arquivo | Destino na imagem | O que faz |
|---|---|---|
| `custom/ChatList.vue` | `app/javascript/dashboard/components/ChatList.vue` | Remove abas Todas/Não atribuídas para agentes |
| `custom/Sidebar.vue` | `app/javascript/.../sidebar/Sidebar.vue` | Remove itens do menu lateral para agentes |
| `custom/LoginIndex.vue` | `app/javascript/v3/views/login/Index.vue` | "Powered by" customizado na tela de login |
| `custom/theme-colors.js` | `theme/colors.js` | Paleta de cores do cliente |
| `custom/conversations_getters.js` | `app/javascript/.../conversations/getters.js` | Frontend: aba Minhas inclui participantes |
| `custom/permission_filter_service.rb` | `app/services/conversations/permission_filter_service.rb` | Backend: controle de acesso por role |
| `custom/conversation_finder.rb` | `app/finders/conversation_finder.rb` | Backend: filtro "Minhas" inclui participantes |
| `custom/_conversation.json.jbuilder` | `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` | API: adiciona campo `is_participant` |
| `custom/saleshub_brand.rb` | `app/config/initializers/saleshub_brand.rb` | Aplica logos no banco ao iniciar |
| `custom/vueapp.html.erb` | `app/views/layouts/vueapp.html.erb` | CSS do tema + fix anti-duplicata Kanban |
| `brand-assets/` | `public/brand-assets/` | Logo, favicon, banner |
