import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { DirectUpload } from 'activestorage';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';

// Limite máximo de upload customizado (ignora limite por canal e valor padrão do globalConfig)
const CUSTOM_MAX_UPLOAD_SIZE_MB = 200;

/**
 * Composable for handling file uploads in conversations
 * @param {Object} options
 * @param {Object} options.inbox - Current inbox object (has channel_type, medium, etc.)
 * @param {Function} options.attachFile - Callback to handle file attachment
 * @param {boolean} options.isPrivateNote - Whether the upload is for a private note
 *
 * CUSTOMIZAÇÃO: removido Math.min(channelLimit, installationLimit) para que o limite
 * por canal (ex: 16 MB WhatsApp) não bloqueie o upload no frontend. O limite real é
 * controlado pelo ATTACHMENT_FILE_MAX_UPLOAD_SIZE no backend (env var = 200 MB).
 */
export const useFileUpload = ({ inbox, attachFile, isPrivateNote = false }) => {
  const { t } = useI18n();

  const accountId = useMapGetter('getCurrentAccountId');
  const currentUser = useMapGetter('getCurrentUser');
  const currentChat = useMapGetter('getSelectedChat');
  const globalConfig = useMapGetter('globalConfig/get');

  // Sempre retorna 200 MB — ignora limites por canal (ex: 16 MB WhatsApp)
  const maxSizeFor = () => CUSTOM_MAX_UPLOAD_SIZE_MB;

  const alertOverLimit = maxSizeMB =>
    useAlert(
      t('CONVERSATION.FILE_SIZE_LIMIT', {
        MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
      })
    );

  const handleDirectFileUpload = file => {
    if (!file) return;

    const maxSizeMB = maxSizeFor();

    if (!checkFileSizeLimit(file, maxSizeMB)) {
      alertOverLimit(maxSizeMB);
      return;
    }

    const upload = new DirectUpload(
      file.file,
      `/api/v1/accounts/${accountId.value}/conversations/${currentChat.value.id}/direct_uploads`,
      {
        directUploadWillCreateBlobWithXHR: xhr => {
          xhr.setRequestHeader(
            'api_access_token',
            currentUser.value.access_token
          );
        },
      }
    );

    upload.create((error, blob) => {
      if (error) {
        useAlert(error);
      } else {
        attachFile({ file, blob });
      }
    });
  };

  const handleIndirectFileUpload = file => {
    if (!file) return;

    const maxSizeMB = maxSizeFor();

    if (!checkFileSizeLimit(file, maxSizeMB)) {
      alertOverLimit(maxSizeMB);
      return;
    }

    attachFile({ file });
  };

  const onFileUpload = file => {
    if (globalConfig.value.directUploadsEnabled) {
      handleDirectFileUpload(file);
    } else {
      handleIndirectFileUpload(file);
    }
  };

  return { onFileUpload };
};
