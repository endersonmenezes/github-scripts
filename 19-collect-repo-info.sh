#!/usr/bin/env bash

###############################################################################
# Script para Coleta de Informações de Repositórios GitHub
#
# Autor: Enderson Menezes
# Criado: 2024-03-08
# Atualizado: 2025-03-12
#
# Descrição:
#   Este script coleta informações relevantes sobre repositórios GitHub
#   e as armazena em um arquivo CSV para análise posterior.
#   As informações coletadas incluem: nome completo, URL, datas de criação
#   e atualização, status de arquivamento, data de arquivamento, último push
#   e tamanho do repositório.
#
# Pré-requisitos:
#   - GitHub CLI (gh) instalado e autenticado
#   - Arquivo CSV de entrada com a lista de repositórios no formato "owner/repo" 
#     (uma entrada por linha)
#
# Uso: bash 19-collect-repo-info.sh
#
# Saída: Arquivo 19-collect-repo-info-result.csv com os dados coletados
###############################################################################

# Carrega funções comuns
source functions.sh

# Configurações
API_VERSION="2022-11-28"
ACCEPT_HEADER="application/vnd.github+json"
OUTPUT_FILE="19-collect-repo-info-result.csv"

###############################################################################
# FUNÇÕES AUXILIARES
###############################################################################

# Função que mostra separador para melhor visualização no console
function show_separator() {
  echo "----------------------------------------"
}

# Função para coletar informações do repositório usando GitHub CLI
function collect_repo_info() {
  local owner=$1
  local repo=$2
  
  echo "Coletando informações para $owner/$repo..."
  
  # Usar gh api para obter informações detalhadas do repositório
  local repo_info=$(gh api \
    --header "Accept: $ACCEPT_HEADER" \
    --header "X-GitHub-Api-Version: $API_VERSION" \
    repos/$owner/$repo)
  
  # Extrair informações necessárias usando jq
  local full_name=$(echo $repo_info | jq -r '.full_name')
  local html_url=$(echo $repo_info | jq -r '.html_url')
  local created_at=$(echo $repo_info | jq -r '.created_at')
  local updated_at=$(echo $repo_info | jq -r '.updated_at')
  local is_archived=$(echo $repo_info | jq -r '.archived')
  local archived_at=$(echo $repo_info | jq -r '.archived_at // "N/A"')
  local pushed_at=$(echo $repo_info | jq -r '.pushed_at')
  local size=$(echo $repo_info | jq -r '.size')
  
  # Adicionar informações ao arquivo CSV
  echo "$full_name, $html_url, $created_at, $updated_at, $is_archived, $archived_at, $pushed_at, $size" >> $OUTPUT_FILE
  
  echo "Informações coletadas com sucesso para $owner/$repo"
}

###############################################################################
# PROGRAMA PRINCIPAL
###############################################################################

# Verifica se o GitHub CLI está instalado
is_gh_installed

# Verifica se o jq está instalado
if ! command -v jq &> /dev/null; then
  echo "O utilitário jq não está instalado. Por favor, instale-o com 'apt-get install jq' ou equivalente."
  exit 1
fi

# Cria um SHA256 do arquivo para auditoria (Define variável SHA256)
audit_file

# Lê arquivo CSV de configuração (Define variável FILE)
read_config_file

# Create CSV com cabeçalho
echo "full_name, html_url, created_at, updated_at, is_archived, archived_at, pushed_at, size" > $OUTPUT_FILE
echo "Criando arquivo de saída: $OUTPUT_FILE"

# Contador para acompanhamento
total_repos=$(cat $FILE | grep -v '^#' | grep -v '^$' | wc -l)
current_repo=0

# Processa cada repositório
for repo_path in $(cat $FILE | grep -v '^#' | grep -v '^$' | awk -F, '{print $1}'); do
  # Extrai o dono e nome do repositório
  OWNER=$(echo $repo_path | awk -F/ '{print $1}')
  REPO=$(echo $repo_path | awk -F/ '{print $2}')

  # Incrementa contador
  ((current_repo++))
  echo "Processando repositório [$current_repo/$total_repos]: $OWNER/$REPO"

  # Collect info to csv
  collect_repo_info $OWNER $REPO
  
  # Mostra separador
  show_separator
done

echo "Processo finalizado! Os resultados foram salvos em $OUTPUT_FILE"
echo "Total de repositórios processados: $current_repo de $total_repos"