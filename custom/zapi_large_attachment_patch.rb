# Patch: transcodar vídeo com FFmpeg antes de enviar pelo Z-API
#
# Problemas originais do WhatsappZapiService:
#   1. Limites fixos de 5 MB (imagens) e 16 MB (áudio/vídeo) → "File too large"
#   2. Vídeos H.265/HEVC (iPhone) incompatíveis com WhatsApp
#   3. Base64 de arquivos >50 MB excede o body limit do Z-API silenciosamente
#
# Esta versão:
#   - VÍDEO: transcodar com FFmpeg → H.264 720p → enviar como base64
#       Fallback: URL pública permanente se FFmpeg falhar ou arquivo ainda grande
#   - IMAGEM / ÁUDIO / DOCUMENTO: URL pública permanente (sem base64)
#   - Qualquer ProviderUnavailableError do Z-API → "Falha ao enviar" visível
#   - Erros inesperados → log completo no Sidekiq + "Falha ao enviar"

require 'open3'
require 'tempfile'
require 'base64'
require 'cgi'

Rails.application.config.after_initialize do
  Whatsapp::Providers::WhatsappZapiService.class_eval do
    private

    # -----------------------------------------------------------------------
    # Ponto de entrada: substitui o método original do Chatwoot
    # -----------------------------------------------------------------------
    def handle_message_with_attachment(message, phone, **params)
      attachment = message.attachments.first

      blob    = attachment.file.blob
      size_mb = (blob.byte_size / 1.megabyte.to_f).round(1)

      # Para vídeo: FFmpeg transcodifica antes de enviar — aceita até 500 MB
      # (153 MB H.265 iPhone → ~20-35 MB H.264 720p após transcode)
      # Para outros tipos: enviados como URL direta ao Z-API — limite de 100 MB
      max_mb = attachment.file_type == 'video' ? 500 : 100

      if blob.byte_size > max_mb.megabytes
        message.update!(status: :failed,
                        external_error: "Arquivo muito grande (#{size_mb} MB, máx #{max_mb} MB para WhatsApp)")
        return
      end

      file_url = zapi_permanent_url(blob)

      Rails.logger.info "[ZapiPatch] Processing #{attachment.file_type} (#{size_mb} MB) " \
                        "for message #{message.id}"

      case attachment.file_type
      when 'image'
        send_image_message(phone, message, file_url, **params)
      when 'audio'
        send_audio_message(phone, message, file_url, **params)
      when 'file'
        send_document_message(phone, message, attachment, file_url, **params)
      when 'video'
        zapi_send_video(message, phone, blob, file_url, **params)
      else
        send_document_message(phone, message, attachment, file_url, **params)
      end
    rescue ProviderUnavailableError => e
      # Z-API rejeitou explicitamente — marcar como falha imediatamente.
      # Sem re-raise: retry do Sidekiq não vai resolver rejeição explícita.
      Rails.logger.error "[ZapiPatch] Z-API rejeitou mídia msg=#{message.id}: #{e.message}"
      message.update(status: :failed,
                     external_error: 'Z-API rejeitou o arquivo. Verifique tamanho e formato.')
    rescue StandardError => e
      # Erro inesperado (falha de disco, OOM, etc.) — logar stacktrace e avisar usuário.
      Rails.logger.error "[ZapiPatch] Erro inesperado msg=#{message.id}: #{e.class}: #{e.message}\n" \
                         "#{e.backtrace&.first(10)&.join('\n')}"
      message.update(status: :failed,
                     external_error: "Erro ao processar o arquivo: #{e.message.truncate(120)}")
      raise # re-raise para o Sidekiq registrar o stacktrace completo no painel
    end

    # -----------------------------------------------------------------------
    # Envio de vídeo: transcodar com FFmpeg, fallback para URL
    # -----------------------------------------------------------------------
    def zapi_send_video(message, phone, blob, fallback_url, **params)
      transcoded_path = zapi_transcode_video(blob)

      if transcoded_path.nil?
        # FFmpeg não disponível ou transcodagem falhou — tenta URL pública
        Rails.logger.warn "[ZapiPatch] Transcode falhou, usando URL para msg=#{message.id}"
        send_video_message(phone, message, fallback_url, **params)
        return
      end

      transcoded_mb = (File.size(transcoded_path) / 1.megabyte.to_f).round(1)
      Rails.logger.info "[ZapiPatch] Transcoded: #{transcoded_mb} MB"

      if File.size(transcoded_path) > 80.megabytes
        # Após transcodagem ainda grande (vídeo muito longo/denso) → tenta URL
        Rails.logger.warn "[ZapiPatch] Transcoded ainda grande (#{transcoded_mb} MB), usando URL msg=#{message.id}"
        send_video_message(phone, message, fallback_url, **params)
      else
        # Envia como base64 — mais confiável que URL para o Z-API
        video_bytes = File.binread(transcoded_path)
        b64_uri     = "data:video/mp4;base64,#{Base64.strict_encode64(video_bytes)}"
        b64_mb      = (b64_uri.bytesize / 1.megabyte.to_f).round(1)
        Rails.logger.info "[ZapiPatch] Enviando base64 (#{transcoded_mb} MB → #{b64_mb} MB b64) msg=#{message.id}"
        send_video_message(phone, message, b64_uri, **params)
      end
    ensure
      # Sempre limpar arquivo temporário, mesmo se ProviderUnavailableError for levantado
      File.unlink(transcoded_path) if transcoded_path && File.exist?(transcoded_path)
    end

    # -----------------------------------------------------------------------
    # Transcodagem FFmpeg: H.264 720p max, AAC 128k, faststart
    # Retorna o path do arquivo transcoded ou nil se qualquer etapa falhar.
    # -----------------------------------------------------------------------
    def zapi_transcode_video(blob)
      # 1. Verificar se ffmpeg está disponível
      _out, _err, status = Open3.capture3('ffmpeg', '-version')
      unless status.success?
        Rails.logger.warn '[ZapiPatch] ffmpeg não encontrado no PATH'
        return nil
      end

      hex          = SecureRandom.hex(8)
      input_path   = "/tmp/zapi_in_#{hex}.tmp"
      output_path  = "/tmp/zapi_out_#{hex}.mp4"

      begin
        # 2. Download do blob para arquivo temporário (streaming para economizar RAM)
        File.open(input_path, 'wb') do |f|
          blob.download { |chunk| f.write(chunk) }
        end

        # 3. Transcodar
        #   -y                      sobrescrever sem confirmação
        #   -loglevel error         silenciar output verbose
        #   -map 0:v:0              forçar primeiro stream de vídeo
        #   -map 0:a:0?             áudio opcional (? = não falhar se não existir)
        #   -c:v libx264 -crf 28    H.264, qualidade boa/tamanho equilibrado
        #   -preset fast            velocidade razoável sem sacrificar muito tamanho
        #   scale=-2:min(720\,ih)   max 720p preservando aspect ratio (largura múltipla de 2)
        #   -c:a aac -b:a 128k      AAC estéreo 128 kbps
        #   -movflags +faststart    mover moov atom para o início (streaming)
        cmd = [
          'ffmpeg', '-y',
          '-loglevel', 'error',
          '-i', input_path,
          '-map', '0:v:0',
          '-map', '0:a:0?',
          '-c:v', 'libx264', '-crf', '28', '-preset', 'fast',
          '-vf', 'scale=-2:min(720\,ih)',
          '-c:a', 'aac', '-b:a', '128k',
          '-movflags', '+faststart',
          output_path
        ]

        _stdout, stderr, ffmpeg_status = Open3.capture3(*cmd)

        unless ffmpeg_status.success?
          Rails.logger.error "[ZapiPatch] ffmpeg falhou (exit #{ffmpeg_status.exitstatus}): #{stderr.truncate(500)}"
          File.unlink(output_path) if File.exist?(output_path)
          return nil
        end

        # 4. Verificar que o arquivo de saída existe e não está vazio
        unless File.exist?(output_path) && File.size(output_path) > 0
          Rails.logger.error '[ZapiPatch] ffmpeg saiu com sucesso mas o arquivo de saída está ausente/vazio'
          return nil
        end

        output_path

      rescue StandardError => e
        Rails.logger.error "[ZapiPatch] zapi_transcode_video erro: #{e.class}: #{e.message}"
        File.unlink(output_path) if File.exist?(output_path)
        nil
      ensure
        # Limpar sempre o arquivo de entrada
        File.unlink(input_path) if File.exist?(input_path)
      end
    end

    # -----------------------------------------------------------------------
    # URL permanente via signed_id — não expira, Rails gera redirect fresco
    # -----------------------------------------------------------------------
    def zapi_permanent_url(blob)
      frontend_url = ENV.fetch('FRONTEND_URL', '').chomp('/')
      "#{frontend_url}/rails/active_storage/blobs/redirect/#{blob.signed_id}/#{CGI.escape(blob.filename.to_s)}"
    end
  end
end
