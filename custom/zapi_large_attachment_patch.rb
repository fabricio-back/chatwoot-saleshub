# Patch: envia attachments via URL pública ao invés de base64
#
# O comportamento original do WhatsappZapiService converte o arquivo inteiro para
# base64 na memória e verifica limites fixos (5 MB imagens, 16 MB áudio/vídeo).
# Arquivos maiores recebem status :failed com external_error "File too large".
#
# Este patch substitui handle_message_with_attachment para passar a URL pública
# do arquivo diretamente ao Z-API. O Z-API suporta URLs além de base64 em todos
# os endpoints (send-image, send-video, send-audio, send-document).
# Resultado: sem limite de tamanho no lado do Chatwoot — o Z-API baixa o arquivo
# a partir da URL pública gerada pelo Active Storage.

Rails.application.config.after_initialize do
  Whatsapp::Providers::WhatsappZapiService.class_eval do
    private

    def handle_message_with_attachment(message, phone, **params)
      attachment = message.attachments.first

      # Z-API hard limit: 100 MB
      if attachment.file.byte_size > 100.megabytes
        message.update!(status: :failed, external_error: "File too large (#{(attachment.file.byte_size / 1.megabyte.to_f).round(1)}MB, max 100MB)")
        return
      end

      # Constrói URL pública permanente usando FRONTEND_URL diretamente.
      # Usa /blobs/redirect/:signed_id/:filename — não expira e Rails gera o
      # redirect para o storage na hora em que o Z-API faz o GET.
      # Isso evita enviar um JSON body de ~133% do tamanho do arquivo (base64).
      frontend_url = ENV.fetch('FRONTEND_URL', '').chomp('/')
      blob = attachment.file.blob
      file_url = "#{frontend_url}/rails/active_storage/blobs/redirect/#{blob.signed_id}/#{CGI.escape(blob.filename.to_s)}"

      Rails.logger.info "[ZapiPatch] Sending #{attachment.file_type} via URL " \
                        "(#{(attachment.file.byte_size / 1.megabyte.to_f).round(1)}MB): #{file_url}"

      case attachment.file_type
      when 'image'
        send_image_message(phone, message, file_url, **params)
      when 'audio'
        send_audio_message(phone, message, file_url, **params)
      when 'file'
        send_document_message(phone, message, attachment, file_url, **params)
      when 'video'
        send_video_message(phone, message, file_url, **params)
      else
        send_document_message(phone, message, attachment, file_url, **params)
      end
    rescue ProviderUnavailableError
      # Marca como falha imediatamente para o usuário ver "Falha ao enviar".
      # Sem re-raise: Z-API rejeitou explicitamente, retry não resolve.
      Rails.logger.error "[ZapiPatch] Z-API rejected media for message #{message.id}"
      message.update(status: :failed, external_error: 'Z-API rejeitou o arquivo. Verifique tamanho e formato.')
    end
  end
end
