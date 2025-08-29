#!/bin/bash

# Nome: 29-download-wiki.sh
# Descrição: Baixa toda a Wiki de um repositório em formato markdown
# Autor: GitHub Copilot e Enderson Menezes
# Data de criação: 13/08/2025
# Última atualização: 13/08/2025
# 
# Uso: bash 29-download-wiki.sh <repository_url_or_name> [output_dir]
# 
# Parâmetros:
#   repository_url_or_name: URL da wiki (ex: https://github.com/dlpco/developers/wiki/) ou nome do repo (ex: dlpco/developers)
#   output_dir: Diretório de saída (opcional, padrão: ./wiki_<repo_name>)
#
# Exemplos:
#   bash 27-download-wiki.sh https://github.com/dlpco/developers/wiki/
#   bash 27-download-wiki.sh dlpco/developers
#   bash 27-download-wiki.sh dlpco/developers /tmp/my_wiki
#
# Requisitos:
#   - GitHub CLI (gh) instalado e autenticado
#   - git instalado
#   - jq instalado para processamento JSON

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir mensagens coloridas
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para verificar dependências
check_dependencies() {
    local deps=("gh" "git" "jq")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Dependências faltando: ${missing_deps[*]}"
        log_error "Instale as dependências e tente novamente"
        exit 1
    fi
}

# Função para verificar autenticação do GitHub CLI
check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI não está autenticado"
        log_error "Execute: gh auth login"
        exit 1
    fi
}

# Função para extrair owner/repo de uma URL
extract_repo_from_url() {
    local url="$1"
    
    # Remove trailing slash se existir
    url="${url%/}"
    
    # Extrai owner/repo de diferentes formatos de URL
    if [[ "$url" =~ https://github\.com/([^/]+)/([^/]+)(/wiki)?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    else
        log_error "Formato de URL inválido: $url"
        log_error "Use o formato: https://github.com/owner/repo/wiki/ ou owner/repo"
        exit 1
    fi
}

# Função para verificar se o repositório existe e tem wiki
check_repo_and_wiki() {
    local repo="$1"
    
    log_info "Verificando repositório: $repo"
    
    # Verifica se o repositório existe
    if ! gh repo view "$repo" &> /dev/null; then
        log_error "Repositório não encontrado ou sem acesso: $repo"
        exit 1
    fi
    
    # Verifica se o repositório tem wiki habilitada
    local has_wiki
    has_wiki=$(gh api "repos/$repo" --jq '.has_wiki')
    
    if [ "$has_wiki" != "true" ]; then
        log_error "Wiki não está habilitada para o repositório: $repo"
        exit 1
    fi
    
    log_success "Repositório encontrado e wiki está habilitada"
}

# Função para obter lista de páginas da wiki
get_wiki_pages() {
    local repo="$1"
    
    log_info "Obtendo lista de páginas da wiki..."
    
    # Faz requisição para obter páginas da wiki
    if ! gh api "repos/$repo/wiki" 2>/dev/null; then
        log_warning "Não foi possível obter páginas via API (repositório pode estar vazio ou wiki privada)"
        return 1
    fi
}

# Função para clonar wiki via git
clone_wiki_git() {
    local repo="$1"
    local output_dir="$2"
    
    log_info "Tentando clonar wiki via git..."
    
    local wiki_url="https://github.com/$repo.wiki.git"
    
    # Remove diretório se já existir
    if [ -d "$output_dir" ]; then
        log_warning "Diretório $output_dir já existe, removendo..."
        rm -rf "$output_dir"
    fi
    
    # Tenta clonar o repositório da wiki
    if git clone "$wiki_url" "$output_dir" 2>/dev/null; then
        log_success "Wiki clonada com sucesso via git"
        return 0
    else
        log_warning "Não foi possível clonar wiki via git (pode não existir ou estar vazia)"
        return 1
    fi
}

# Função para baixar páginas individuais via API
download_pages_api() {
    local repo="$1"
    local output_dir="$2"
    
    log_info "Baixando páginas via API do GitHub..."
    
    # Cria diretório de saída
    mkdir -p "$output_dir"
    
    # Obtém lista de páginas
    local pages_json
    if ! pages_json=$(gh api "repos/$repo/wiki" 2>/dev/null); then
        log_error "Erro ao obter lista de páginas da wiki"
        return 1
    fi
    
    # Verifica se há páginas
    local page_count
    page_count=$(echo "$pages_json" | jq '. | length')
    
    if [ "$page_count" -eq 0 ]; then
        log_warning "Wiki não contém páginas"
        return 1
    fi
    
    log_info "Encontradas $page_count páginas na wiki"
    
    # Baixa cada página
    echo "$pages_json" | jq -r '.[] | .title' | while read -r page_title; do
        log_info "Baixando página: $page_title"
        
        # Obtém conteúdo da página
        local page_content
        if page_content=$(gh api "repos/$repo/wiki/$page_title" --jq '.content' 2>/dev/null); then
            # Salva página em arquivo
            local filename="${page_title// /-}.md"
            echo "$page_content" > "$output_dir/$filename"
            log_success "Página salva: $filename"
        else
            log_warning "Erro ao baixar página: $page_title"
        fi
    done
    
    return 0
}

# Função para criar índice das páginas
create_index() {
    local output_dir="$1"
    local repo="$2"
    
    log_info "Criando índice das páginas..."
    
    local index_file="$output_dir/README.md"
    
    cat > "$index_file" << EOF
# Wiki - $repo

Este diretório contém todas as páginas da wiki do repositório [$repo](https://github.com/$repo).

**Data de download:** $(date '+%Y-%m-%d %H:%M:%S')

## Páginas disponíveis

EOF
    
    # Lista arquivos markdown no diretório
    if ls "$output_dir"/*.md &> /dev/null; then
        for file in "$output_dir"/*.md; do
            if [ "$(basename "$file")" != "README.md" ]; then
                local basename_file
                basename_file=$(basename "$file" .md)
                local title="${basename_file//-/ }"
                echo "- [$title]($basename_file.md)" >> "$index_file"
            fi
        done
    fi
    
    cat >> "$index_file" << EOF

---

*Baixado usando o script 29-download-wiki.sh*
EOF
    
    log_success "Índice criado: README.md"
}

# Função para exibir estatísticas
show_statistics() {
    local output_dir="$1"
    local repo="$2"
    
    if [ ! -d "$output_dir" ]; then
        return
    fi
    
    local file_count
    file_count=$(find "$output_dir" -name "*.md" | wc -l)
    
    local total_size
    total_size=$(du -sh "$output_dir" | cut -f1)
    
    echo
    log_success "Download concluído!"
    echo "├── Repositório: $repo"
    echo "├── Diretório: $output_dir"
    echo "├── Páginas baixadas: $file_count"
    echo "└── Tamanho total: $total_size"
    echo
}

# Função principal
main() {
    local input="$1"
    local output_dir="${2:-}"
    
    # Verifica dependências
    check_dependencies
    check_gh_auth
    
    # Extrai repositório da entrada
    local repo
    if [[ "$input" =~ ^https://github\.com/ ]]; then
        repo=$(extract_repo_from_url "$input")
    elif [[ "$input" =~ ^[^/]+/[^/]+$ ]]; then
        repo="$input"
    else
        log_error "Formato inválido. Use: https://github.com/owner/repo/wiki/ ou owner/repo"
        exit 1
    fi
    
    # Define diretório de saída
    if [ -z "$output_dir" ]; then
        local repo_name
        repo_name=$(echo "$repo" | cut -d'/' -f2)
        output_dir="./wiki_$repo_name"
    fi
    
    log_info "Iniciando download da wiki de $repo para $output_dir"
    
    # Verifica repositório e wiki
    check_repo_and_wiki "$repo"
    
    # Tenta diferentes métodos de download
    local success=false
    
    # Método 1: Clone via git (mais completo)
    if clone_wiki_git "$repo" "$output_dir"; then
        success=true
    else
        # Método 2: Download via API (fallback)
        if download_pages_api "$repo" "$output_dir"; then
            success=true
        fi
    fi
    
    if [ "$success" = true ]; then
        # Cria índice
        create_index "$output_dir" "$repo"
        
        # Exibe estatísticas
        show_statistics "$output_dir" "$repo"
        
        log_success "Wiki baixada com sucesso em: $output_dir"
    else
        log_error "Não foi possível baixar a wiki"
        log_error "Possíveis causas:"
        log_error "  - Wiki está vazia"
        log_error "  - Wiki é privada e você não tem acesso"
        log_error "  - Problemas de conectividade"
        exit 1
    fi
}

# Função para exibir ajuda
show_help() {
    cat << EOF
Uso: $0 <repository_url_or_name> [output_dir]

Baixa toda a Wiki de um repositório do GitHub em formato markdown.

PARÂMETROS:
  repository_url_or_name  URL da wiki ou nome do repositório
                         Exemplos:
                           https://github.com/dlpco/developers/wiki/
                           dlpco/developers
  
  output_dir             Diretório de saída (opcional)
                         Padrão: ./wiki_<repo_name>

EXEMPLOS:
  $0 https://github.com/dlpco/developers/wiki/
  $0 dlpco/developers
  $0 dlpco/developers /tmp/my_wiki

REQUISITOS:
  - GitHub CLI (gh) instalado e autenticado
  - git instalado
  - jq instalado

MÉTODOS DE DOWNLOAD:
  1. Clone via git (preferido) - mantém histórico e metadados
  2. API do GitHub (fallback) - baixa conteúdo atual das páginas

O script tenta ambos os métodos automaticamente.
EOF
}

# Verifica argumentos
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    log_error "Número incorreto de argumentos"
    show_help
    exit 1
fi

# Executa função principal
main "$@"
