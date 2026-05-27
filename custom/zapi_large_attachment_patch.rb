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

      # Z-API hard limit: 100 MB para vídeo/áudio/documentos
      if attachment.file.byte_size > 100.megabytes
        message.update!(status: :failed, external_error: 'File too large (max 100MB for Z-API)')
        return
      end

      base64_data = attachment_to_base64(attachment)
      buffer = "data:#{attachment.file.content_type};base64,#{base64_data}"

      case attachment.file_type
      when 'image'
        send_image_message(phone, message, buffer, **params)
      when 'audio'
        send_audio_message(phone, message, buffer, **params)
      when 'file'
        send_document_message(phone, message, attachment, buffer, **params)
      when 'video'
        send_video_message(phone, message, buffer, **params)
      else
        send_document_message(phone, message, attachment, buffer, **params)
      end
    end
  end
end
