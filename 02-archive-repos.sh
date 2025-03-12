#!/usr/bin/env bash

###############################################################################
# Script para Arquivamento de Repositórios com tratamento de alertas de segurança
#
# Autor: Enderson Menezes
# Criado: 2024-03-08
# Atualizado: 2025-03-12
#
# Descrição:
#   Este script prepara repositórios para arquivamento realizando as seguintes ações:
#   1. Lista e fecha alertas de Dependabot
#   2. Lista e fecha alertas de Code Scanning
#   3. Remove acesso de equipes e colaboradores
#   4. Arquiva o repositório (comentado)
#
# Uso: bash 02-archive-repos.sh
###############################################################################

# Carrega funções comuns
source functions.sh

# Configurações
API_VERSION="2022-11-28"
ACCEPT_HEADER="application/vnd.github+json"

###############################################################################
# FUNÇÕES AUXILIARES
###############################################################################

# Função que mostra separador para melhor visualização no console
function show_separator() {
  echo "----------------------------------------"
}

# Função que processa alertas do Dependabot
function process_dependabot_alerts() {
  local owner=$1
  local repo=$2

  echo "Listando alertas do Dependabot para $owner/$repo..."
  local alerts=$(gh api \
    -H "Accept: $ACCEPT_HEADER" \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    -- paginate \
    "/repos/$owner/$repo/dependabot/alerts?state=open" | jq -r '.[] | .number')
  
  # Fecha os alertas do Dependabot
  if [ -n "$alerts" ]; then
    local count=$(echo "$alerts" | wc -l | tr -d ' ')
    echo "Encontrados $count alertas abertos do Dependabot"
    
    for alert_number in $alerts; do
      echo "Fechando alerta do Dependabot #$alert_number"
      gh api --method PATCH \
        -H "Accept: $ACCEPT_HEADER" \
        -H "X-GitHub-Api-Version: $API_VERSION" \
        "/repos/$owner/$repo/dependabot/alerts/$alert_number" \
        -f state="dismissed" \
        -f dismissed_reason="not_used" \
        -f dismissed_comment="Este alerta foi fechado automaticamente mediante ao arquivamento do repositório" > /dev/null
    done
  else
    echo "Nenhum alerta aberto do Dependabot encontrado"
  fi
}

# Função que processa alertas do Code Scanning
function process_code_scanning_alerts() {
  local owner=$1
  local repo=$2

  echo "Listando alertas do Code Scanning para $owner/$repo..."
  local alerts=$(gh api \
    -H "Accept: $ACCEPT_HEADER" \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    --paginate \
    "/repos/$owner/$repo/code-scanning/alerts?state=open" | jq -r '.[] | .number')

  # Fecha os alertas do Code Scanning
  if [ -n "$alerts" ]; then
    local count=$(echo "$alerts" | wc -l | tr -d ' ')
    echo "Encontrados $count alertas abertos do Code Scanning"
    
    for alert_number in $alerts; do
      echo "Fechando alerta do Code Scanning #$alert_number"
      gh api --method PATCH \
        -H "Accept: $ACCEPT_HEADER" \
        -H "X-GitHub-Api-Version: $API_VERSION" \
        "/repos/$owner/$repo/code-scanning/alerts/$alert_number" \
        -f state="dismissed" \
        -f dismissed_reason="won't fix" \
        -f dismissed_comment="Este alerta foi fechado automaticamente mediante ao arquivamento do repositório" > /dev/null
    done
  else
    echo "Nenhum alerta aberto do Code Scanning encontrado"
  fi
}

# Função para remover acesso de equipes
function remove_team_access() {
  local owner=$1
  local repo=$2
  local teams_file="teams_${owner}_${repo}.json"
  
  echo "Removendo acesso de equipes do repositório $owner/$repo"
  
  # Obter todas as equipes com acesso
  gh api "/repos/${owner}/${repo}/teams" > "$teams_file"
  
  for team in $(jq -r '.[].slug' "$teams_file"); do
    echo "- Removendo acesso da equipe: ${team}"
    gh api \
      --method DELETE \
      -H "Accept: $ACCEPT_HEADER" \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "/orgs/${owner}/teams/${team}/repos/${owner}/${repo}" > /dev/null
  done
  
  # Limpa o arquivo temporário
  rm -f "$teams_file"
}

# Função para remover acesso de colaboradores diretos
function remove_direct_collaborators() {
  local owner=$1
  local repo=$2
  local collab_file="collaborators_${owner}_${repo}.json"
  
  echo "Removendo acesso de colaboradores diretos do repositório $owner/$repo"
  
  # Obter todos os colaboradores diretos
  gh api "/repos/${owner}/${repo}/collaborators?affiliation=direct" --paginate > "$collab_file"
  
  for collaborator in $(jq -r '.[].login' "$collab_file"); do
    echo "- Removendo acesso do colaborador: ${collaborator}"
    gh api \
      --method DELETE \
      -H "Accept: $ACCEPT_HEADER" \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "/repos/${owner}/${repo}/collaborators/${collaborator}" > /dev/null
  done
  
  # Limpa o arquivo temporário
  rm -f "$collab_file"
}

# Função para arquivar o repositório
function archive_repository() {
  local owner=$1
  local repo=$2
  
  echo "Arquivando repositório $owner/$repo..."
  # gh repo archive $owner/$repo -y
  echo "Repositório $owner/$repo foi arquivado (SIMULADO)"
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
  
  # Processa os alertas de segurança
  process_dependabot_alerts $OWNER $REPO
  process_code_scanning_alerts $OWNER $REPO
  
  # Remove acessos
  remove_team_access $OWNER $REPO
  remove_direct_collaborators $OWNER $REPO
  
  # Arquiva o repositório (comentado conforme solicitado)
  archive_repository $OWNER $REPO
  
  # Mostra separador
  show_separator
done

echo "Processo finalizado!"