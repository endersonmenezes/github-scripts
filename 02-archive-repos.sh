#!/usr/bin/env bash

###############################################################################
# Script para Arquivamento de Repositórios com Tratamento de Alertas de Segurança
#
# Autor: Enderson Menezes
# Criado: 2024-03-08
# Atualizado: 2025-03-14
#
# Descrição:
#   Este script prepara repositórios para arquivamento realizando as seguintes ações:
#   1. Lista e fecha alertas de Dependabot com motivo "não utilizado"
#   2. Lista e fecha alertas de Code Scanning com motivo "não será corrigido"
#   3. Remove acesso de equipes e colaboradores diretos
#   4. Arquiva o repositório
#
# Formato do CSV:
#   - Sem cabeçalho
#   - Uma linha por repositório no formato: owner/repo
#
# Uso: bash 02-archive-repos.sh
###############################################################################

# Carrega funções comuns
source functions.sh

# Configurações da API do GitHub
API_VERSION="2022-11-28"
ACCEPT_HEADER="application/vnd.github+json"

###############################################################################
# FUNÇÕES AUXILIARES
###############################################################################

# Função que mostra separador para melhor visualização no console
function show_separator() {
  echo "----------------------------------------"
}

# Função que processa e fecha alertas do Dependabot
function process_dependabot_alerts() {
  local owner=$1
  local repo=$2

  echo "Listando alertas do Dependabot para $owner/$repo..."
  local alerts=$(gh api \
    -H "Accept: $ACCEPT_HEADER" \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    --paginate \
    "/repos/$owner/$repo/dependabot/alerts?state=open" | jq -r '.[] | .number')
  
  # Fecha os alertas do Dependabot com motivo "not_used"
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

# Função que processa e fecha alertas do Code Scanning
function process_code_scanning_alerts() {
  local owner=$1
  local repo=$2

  echo "Listando alertas do Code Scanning para $owner/$repo..."
  local alerts=$(gh api \
    -H "Accept: $ACCEPT_HEADER" \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    --paginate \
    "/repos/$owner/$repo/code-scanning/alerts?state=open" | jq -r '.[] | .number')

  # Fecha os alertas do Code Scanning com motivo "won't fix"
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

# Função para remover acesso de equipes do repositório
function remove_team_access() {
  local owner=$1
  local repo=$2
  local teams_file="teams_${owner}_${repo}.json"
  
  echo "Removendo acesso de equipes do repositório $owner/$repo"
  
  # Obtém todas as equipes com acesso ao repositório
  gh api "/repos/${owner}/${repo}/teams" > "$teams_file"

  # Verifica se existe alguma equipe com permissão de "Repository owner"
  if [ $(jq -r '.[].permission' "$teams_file" | grep -c 'Repository owner') -gt 0 ]; then
    echo "O repositório possui equipes com permissão de administrador, não será necessário arquivar."
    return 1
  fi
  
  # Remove acesso de cada equipe encontrada
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

# Função para remover acesso de colaboradores diretos do repositório
function remove_direct_collaborators() {
  local owner=$1
  local repo=$2
  local collab_file="collaborators_${owner}_${repo}.json"
  
  echo "Removendo acesso de colaboradores diretos do repositório $owner/$repo"
  
  # Obtém todos os colaboradores diretos do repositório
  gh api "/repos/${owner}/${repo}/collaborators?affiliation=direct" --paginate > "$collab_file"
  
  # Remove acesso de cada colaborador direto
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
  gh repo archive $owner/$repo -y
  echo "Repositório $owner/$repo foi arquivado com sucesso"
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

# Processa cada repositório listado no arquivo CSV
for repo_path in $(cat $FILE | grep -v '^#' | grep -v '^$' | awk -F, '{print $1}'); do
  # Extrai o dono e nome do repositório
  OWNER=$(echo $repo_path | awk -F/ '{print $1}')
  REPO=$(echo $repo_path | awk -F/ '{print $2}')

  echo "Processando repositório: $OWNER/$REPO"

  # Valida se o repositório já está arquivado
  if [ "$(gh repo view $OWNER/$REPO --json isArchived --jq '.isArchived')" = "true" ]; then
    echo "Repositório já está arquivado, pulando para o próximo..."
    show_separator
    continue
  fi

  # Remove acessos de equipes e verifica permissões de administrador
  remove_team_access $OWNER $REPO
  if [ $? -eq 1 ]; then
    echo "Pulando para o próximo repositório devido à presença de equipes administradoras..."
    show_separator
    continue
  fi

  # Remove acessos de colaboradores diretos
  remove_direct_collaborators $OWNER $REPO
  
  # Processa os alertas de segurança
  process_dependabot_alerts $OWNER $REPO
  process_code_scanning_alerts $OWNER $REPO
  
  # Arquiva o repositório
  archive_repository $OWNER $REPO
  
  # Mostra separador para melhor visualização
  show_separator
done

echo "Processo finalizado com sucesso!"