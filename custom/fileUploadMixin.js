import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { DirectUpload } from 'activestorage';

// Limite máximo de upload customizado (ignora limite por canal e valor padrão do globalConfig)
const CUSTOM_MAX_UPLOAD_SIZE_MB = 200;

/**
 * CUSTOMIZAÇÃO: removido Math.min(channelLimit, installationLimit) para que o limite
 * por canal (ex: 16 MB WhatsApp imagem/vídeo) não bloqueie o upload no frontend.
 * O limite real é controlado pelo ATTACHMENT_FILE_MAX_UPLOAD_SIZE no backend (200 MB).
 */
export default {
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
    }),
  },

  methods: {
    maxSizeFor(_mime) {
      return CUSTOM_MAX_UPLOAD_SIZE_MB;
    },
    alertOverLimit(maxSizeMB) {
      useAlert(
        this.$t('CONVERSATION.FILE_SIZE_LIMIT', {
          MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
        })
      );
    },
    onFileUpload(file) {
      if (this.globalConfig.directUploadsEnabled) {
        this.onDirectFileUpload(file);
      } else {
        this.onIndirectFileUpload(file);
      }
    },

    onDirectFileUpload(file) {
      if (!file) return;

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return;
      }

      const upload = new DirectUpload(
        file.file,
        `/api/v1/accounts/${this.accountId}/conversations/${this.currentChat.id}/direct_uploads`,
        {
          directUploadWillCreateBlobWithXHR: xhr => {
            xhr.setRequestHeader(
              'api_access_token',
              this.currentUser.access_token
            );
          },
        }
      );

      upload.create((error, blob) => {
        if (error) {
          useAlert(error);
        } else {
          this.attachFile({ file, blob });
        }
      });
    },

    onIndirectFileUpload(file) {
      if (!file) return;

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return;
      }

      this.attachFile({ file });
    },
  },
};
