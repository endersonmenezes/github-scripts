#!/usr/bin/env bash

###############################################################################
# Script para Deleção de Repositórios Vazios (com tamanho menor que 1MB)
#
# Autor: Enderson Menezes
# Criado: 2024-03-08
# Atualizado: 2025-03-12
#
# Descrição:
#   Este script identifica e remove repositórios vazios ou muito pequenos (menos de 1MB),
#   realizando as seguintes ações:
#   1. Verifica o tamanho do repositório usando a API do GitHub
#   2. Se o tamanho for menor que 1MB, deleta o repositório permanentemente
#   3. Se for maior, ignora e continua para o próximo
#
# Uso: bash 18-delete-repo-sizeless.sh
###############################################################################

# Carrega funções comuns
source functions.sh

# Configurações
API_VERSION="2022-11-28"
ACCEPT_HEADER="application/vnd.github+json"

# Função para deletar o repositório
function delete_repo() {
  local owner=$1
  local repo=$2
  
  echo "Deletando repositório $owner/$repo..."
  gh repo delete $owner/$repo --yes
  echo "Repositório $owner/$repo foi deletado"
}

# Função que mostra separador para melhor visualização no console
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

  # Verifica o tamanho do repositório na API do GitHub
  SIZE=$(gh api \
      -H "Accept: $ACCEPT_HEADER" \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "/repos/$OWNER/$REPO" | jq -r '.size')
  
  # Só deleta repositórios com menos de 1MB
  if [ $SIZE -gt 1 ]; then
    echo "Repositório $OWNER/$REPO possui tamanho maior que 1MB - ignorando"
    continue
  fi

  # Deleta o repositório se for menor que 1MB
  delete_repo $OWNER $REPO
  
  # Mostra separador
  show_separator
done

echo "Processo finalizado!"