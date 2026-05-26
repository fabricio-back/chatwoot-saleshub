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

      # Gera URL pública com assinatura temporária (Active Storage).
      # Usa FRONTEND_URL como host base (configurado via env var).
      file_url = attachment.download_url

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
    end
  end
end
