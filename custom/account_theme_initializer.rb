# Inicializador: cria a rota e controller que servem CSS dinâmico de cores
# por conta, lendo custom_attributes['theme_primary_color'].
#
# Rota:  GET /account_theme/:account_id  →  AccountThemeController#show
# Saída: text/css com variáveis CSS sobrescrevendo o tema padrão
#
# Uso no frontend: script em vueapp.html.erb detecta account_id na URL e
# carrega <link rel="stylesheet" href="/account_theme/:id"> dinamicamente.

# ------------------------------------------------------------------
# Helpers de cor (sem gem externa)
# ------------------------------------------------------------------
module ThemeColorHelper
  HEX_RE = /\A#([0-9a-fA-F]{6})\z/

  def self.valid_hex?(hex)
    HEX_RE.match?(hex.to_s)
  end

  def self.parse(hex)
    m = HEX_RE.match(hex.to_s)
    return nil unless m
    [m[1][0..1].to_i(16), m[1][2..3].to_i(16), m[1][4..5].to_i(16)]
  end

  def self.to_hex(r, g, b)
    '#' + [r, g, b].map { |c| c.clamp(0, 255).to_s(16).rjust(2, '0') }.join
  end

  # Mistura a cor com branco (ratio = 0..1, quanto de branco)
  def self.lighten(r, g, b, ratio)
    [
      (r + (255 - r) * ratio).round,
      (g + (255 - g) * ratio).round,
      (b + (255 - b) * ratio).round,
    ]
  end

  # Mistura a cor com preto (ratio = 0..1, quanto de preto)
  def self.darken(r, g, b, ratio)
    [
      (r * (1 - ratio)).round,
      (g * (1 - ratio)).round,
      (b * (1 - ratio)).round,
    ]
  end

  # Gera escala completa de tonalidades a partir de um HEX
  # Retorna hash { 25 => '#hex', 50 => '#hex', … 900 => '#hex' }
  def self.scale(hex)
    rgb = parse(hex)
    return nil unless rgb
    r, g, b = rgb

    {
      25  => to_hex(*lighten(r, g, b, 0.96)),
      50  => to_hex(*lighten(r, g, b, 0.88)),
      75  => to_hex(*lighten(r, g, b, 0.75)),
      100 => to_hex(*lighten(r, g, b, 0.60)),
      200 => to_hex(*lighten(r, g, b, 0.40)),
      300 => to_hex(*lighten(r, g, b, 0.20)),
      400 => to_hex(*lighten(r, g, b, 0.08)),
      500 => hex,
      600 => to_hex(*darken(r, g, b, 0.10)),
      700 => to_hex(*darken(r, g, b, 0.28)),
      800 => to_hex(*darken(r, g, b, 0.48)),
      900 => to_hex(*darken(r, g, b, 0.62)),
    }
  end
end

# ------------------------------------------------------------------
# Controller (definido inline — sem arquivo separado)
# ------------------------------------------------------------------
begin
class AccountThemeController < ActionController::Base
  # Tempo de cache do CSS no browser (1 hora). O script no frontend
  # invalida por query string ao trocar de conta.
  CACHE_TTL = 1.hour

  def show
    account = Account.find_by(id: params[:account_id])

    expires_in CACHE_TTL, public: false
    render plain: build_css(account), content_type: 'text/css'
  end

  private

  def build_css(account)
    attrs = account&.custom_attributes || {}
    primary = attrs['theme_primary_color'].to_s.strip

    return '/* sem tema customizado */' unless ThemeColorHelper.valid_hex?(primary)

    scale = ThemeColorHelper.scale(primary)

    <<~CSS
      /* Tema dinâmico gerado para a conta #{account&.id} */
      :root {
        --color-woot:        #{scale[500]};
        --color-woot-medium: #{scale[700]};
        --color-woot-dark:   #{scale[900]};
        --theme-color:       #{scale[500]};

        --w-25:  #{scale[25]};
        --w-50:  #{scale[50]};
        --w-75:  #{scale[75]};
        --w-100: #{scale[100]};
        --w-200: #{scale[200]};
        --w-300: #{scale[300]};
        --w-400: #{scale[400]};
        --w-500: #{scale[500]};
        --w-600: #{scale[600]};
        --w-700: #{scale[700]};
        --w-800: #{scale[800]};
        --w-900: #{scale[900]};
      }

      /* Botões primários */
      .button.nice.success,
      .button.primary,
      [class*="bg-woot-500"],
      [class*="bg-woot-600"] {
        background-color: #{scale[500]} !important;
        border-color:     #{scale[500]} !important;
      }
      [class*="bg-woot-700"],
      [class*="bg-woot-800"] {
        background-color: #{scale[700]} !important;
        border-color:     #{scale[700]} !important;
      }

      /* Links e textos coloridos */
      [class*="text-woot-500"],
      [class*="text-woot-600"] { color: #{scale[500]} !important; }
      [class*="text-woot-700"],
      [class*="text-woot-800"],
      [class*="text-woot-900"] { color: #{scale[700]} !important; }

      /* Bordas / outlines */
      [class*="border-woot-500"],
      [class*="border-woot-600"] { border-color: #{scale[500]} !important; }

      /* Aba ativa e indicadores */
      [class*="border-b-woot"],
      .active-tab,
      [class*="active"][class*="woot"] {
        border-color: #{scale[500]} !important;
        color:        #{scale[500]} !important;
      }

      /* Checkbox / radio */
      input[type="checkbox"]:checked,
      input[type="radio"]:checked { accent-color: #{scale[500]}; }

      /* Scrollbar */
      ::-webkit-scrollbar-thumb       { background-color: #{scale[200]}; }
      ::-webkit-scrollbar-thumb:hover { background-color: #{scale[500]}; }
    CSS
  end
end

# ------------------------------------------------------------------
# Rota (adicionada ao router existente sem substituir)
# ------------------------------------------------------------------
Rails.application.routes.prepend do
  get 'account_theme/:account_id', to: 'account_theme#show', defaults: { format: :css }
end

rescue StandardError => e
  Rails.logger.error "[account_theme_initializer] Falha ao carregar (app continua): #{e.class}: #{e.message}"
  Rails.logger.error e.backtrace.first(10).join("\n") rescue nil
end
