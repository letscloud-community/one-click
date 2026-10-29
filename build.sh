#!/bin/bash
#
# Build helper for the LetsCloud one-click images.
#
# Reads the API token from ~/.letscloud_token instead of prompting, so a build
# can be launched without an interactive step. The file is never committed and
# must be readable only by its owner.
#
# First time setup, run this yourself in a terminal:
#
#   install -m 600 /dev/null ~/.letscloud_token
#   read -rsp 'Token: ' T && printf '%s' "$T" > ~/.letscloud_token && unset T
#
# Usage:
#   ./build.sh dragonwilds-24-04
#   ./build.sh dragonwilds-24-04 --validate-only

set -euo pipefail

TOKEN_FILE="${LETSCLOUD_TOKEN_FILE:-$HOME/.letscloud_token}"
IMAGE="${1:-}"
MODE="${2:-build}"

die() { echo "ERRO: $*" >&2; exit 1; }

[ -n "${IMAGE}" ] || die "Informe a imagem. Exemplo: ./build.sh dragonwilds-24-04"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="${REPO_DIR}/${IMAGE}"
[ -d "${IMAGE_DIR}" ] || die "Diretorio nao encontrado: ${IMAGE_DIR}"

if [ ! -f "${TOKEN_FILE}" ]; then
  cat >&2 <<EOF
ERRO: token nao encontrado em ${TOKEN_FILE}

Rode ESTE comando voce mesmo, uma unica vez, e cole o token quando pedir:

  install -m 600 /dev/null ~/.letscloud_token
  read -rsp 'Token: ' T && printf '%s' "\$T" > ~/.letscloud_token && unset T

Depois execute novamente: ./build.sh ${IMAGE}
EOF
  exit 1
fi

# Refuse to use a token that other users on the box can read.
PERMS="$(stat -c '%a' "${TOKEN_FILE}")"
if [ "${PERMS}" != "600" ] && [ "${PERMS}" != "400" ]; then
  echo "AVISO: ${TOKEN_FILE} esta com permissao ${PERMS}; corrigindo para 600." >&2
  chmod 600 "${TOKEN_FILE}"
fi

# Strip any trailing newline the editor or shell may have added.
API_KEY="$(tr -d '[:space:]' < "${TOKEN_FILE}")"
[ -n "${API_KEY}" ] || die "${TOKEN_FILE} esta vazio."

cd "${IMAGE_DIR}"

echo "Imagem:  ${IMAGE}"
echo "Token:   ${#API_KEY} caracteres, lido de ${TOKEN_FILE}"
echo "Inicio:  $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

packer init . >/dev/null
packer validate -var "api_key=${API_KEY}" . || die "Template invalido."
echo "Validacao OK."

if [ "${MODE}" = "--validate-only" ]; then
  echo "Modo validacao apenas; nada foi construido."
  exit 0
fi

echo "Iniciando build..."
echo ""

# The token is passed through the environment rather than argv, so it does not
# show up in the process list.
PKR_VAR_api_key="${API_KEY}" packer build . 2>&1 \
  | tee packer-build.log \
  | grep -vE 'letscloud\.[a-z0-9-]+: +(Get:|Preparing to unpack|Unpacking |Setting up |Selecting |Processing triggers|Reading |Building dep)'

echo ""
echo "Fim: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log completo: ${IMAGE_DIR}/packer-build.log"
