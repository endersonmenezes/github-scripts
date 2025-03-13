#!/usr/bin/env bash

###############################################################################
# Script para Exclusão de Repositórios Pequenos (menos de 1MB)
#
# Autor: Enderson Menezes
# Criado: 2024-03-08
# Atualizado: 2025-03-12
#
# Descrição:
#   Este script exclui repositórios pequenos que possuem menos de 1MB de tamanho.
#   O script executa as seguintes ações:
#   1. Verifica o tamanho do repositório via API do GitHub
#   2. Se o tamanho for menor que 1MB, exclui o repositório
#   3. Se o tamanho for maior, pula para o próximo repositório
#
# Uso: bash 18-delete-repo-sizeless.sh
###############################################################################

# Carrega funções comuns
source functions.sh

# Configurações
API_VERSION="2022-11-28"
ACCEPT_HEADER="application/vnd.github+json"

# Função para excluir o repositório
function delete_repo() {
  local owner=$1
  local repo=$2
  
  echo "Deletando repositório $owner/$repo..."
  gh repo delete $owner/$repo --yes
  echo "Repositório $owner/$repo foi deletado"
}

function show_separator() {
  echo "----------------------------------------"
}

###############################################################################
# PROGRAMA PRINCIPAL
###############################################################################

# Verifica se o GitHub CLI está instalado
is_gh_installed

# Cria um SHA256 do arquivo para auditoria (Define variável SHA256)
audit_file

# Lê arquivo CSV de configuração (Define variável FILE)
read_config_file

# Processa cada repositório
for repo_path in $(cat $FILE | grep -v '^#' | grep -v '^$' | awk -F, '{print $1}'); do
  # Extrai o dono e nome do repositório
  OWNER=$(echo $repo_path | awk -F/ '{print $1}')
  REPO=$(echo $repo_path | awk -F/ '{print $2}')
  echo "Processando repositório: $OWNER/$REPO"

  # Verifica se o tamanho do repositório é menor que 1MB
  SIZE=$(gh api \
      -H "Accept: $ACCEPT_HEADER" \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "/repos/$OWNER/$REPO" | jq -r '.size')
  
  if [ $SIZE -gt 1 ]; then
    echo "Repositório $OWNER/$REPO possui tamanho maior que 1MB"
    continue
  fi

  # Exclui o repositório se for menor que 1MB
  delete_repo $OWNER $REPO
  
  # Mostra separador
  show_separator
done

echo "Processo finalizado!"