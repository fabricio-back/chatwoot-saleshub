# Script de build da imagem customizada SalesHub
# Uso: .\build.ps1 -Version v1.15
# Sempre puxa a ultima versao da imagem base do fazer.ai antes de buildar

param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

$IMAGE = "ghcr.io/fabricio-back/chatwoot-saleshub"
$LOCAL  = "meu-chatwoot-custom"

Write-Host "==> Atualizando imagem base do fazer.ai..." -ForegroundColor Cyan
docker pull ghcr.io/fazer-ai/chatwoot:latest
if ($LASTEXITCODE -ne 0) { Write-Error "Falha ao baixar imagem base"; exit 1 }

Write-Host "==> Buildando $LOCAL`:$Version ..." -ForegroundColor Cyan
docker build --pull -f Dockerfile.full -t "${LOCAL}:${Version}" .
if ($LASTEXITCODE -ne 0) { Write-Error "Falha no build"; exit 1 }

Write-Host "==> Tagueando como latest para producao..." -ForegroundColor Cyan
docker tag "${LOCAL}:${Version}" "${IMAGE}:latest"

Write-Host "==> Atualizando docker-compose.yml local..." -ForegroundColor Cyan
(Get-Content docker-compose.yml) -replace "${LOCAL}:v\d+\.\d+", "${LOCAL}:${Version}" | Set-Content docker-compose.yml

Write-Host "==> Fazendo push para ghcr.io..." -ForegroundColor Cyan
docker push "${IMAGE}:latest"
if ($LASTEXITCODE -ne 0) { Write-Error "Falha no push. Verifique o login: docker login ghcr.io -u fabricio-back"; exit 1 }

Write-Host ""
Write-Host "✔ Build $Version concluido e enviado para producao!" -ForegroundColor Green
Write-Host "  Imagem local : ${LOCAL}:${Version}"
Write-Host "  Imagem remote: ${IMAGE}:latest"
Write-Host ""
Write-Host "Proximo passo: clique em Redeploy no Coolify." -ForegroundColor Yellow
