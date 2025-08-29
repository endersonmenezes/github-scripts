# AGENTS.md - Diretrizes de Desenvolvimento para IA

## 🚀 Visão Geral do Projeto

Este repositório contém scripts de automação para GitHub e Azure DevOps, desenvolvido por **endersonmenezes** para gerenciamento em escala de organizações, repositórios e equipes.

## 🔒 Política de Segurança CRÍTICA

### ⚠️ NUNCA COMMITAR DADOS SENSÍVEIS

**REGRA ABSOLUTA**: Este é um repositório **PÚBLICO**. Jamais adicionar ao Git:

- ❌ Arquivos `.csv` com dados reais (emails, tokens, nomes de orgs privadas)
- ❌ Arquivos `.json` com respostas de API
- ❌ Arquivos `.txt` com logs ou outputs
- ❌ Tokens, credenciais ou informações confidenciais

### ✅ O que PODE ser commitado:

- ✅ Scripts `.sh` e `.py` (código-fonte)
- ✅ Arquivos `.example.csv` (templates sem dados reais)
- ✅ Documentação `.md`
- ✅ Arquivos de configuração sem credenciais

### 📋 Verificação de Segurança

Antes de qualquer commit, sempre verificar:

```bash
# Verificar o que será commitado
git status
git diff --cached

# Confirmar que apenas arquivos seguros estão sendo adicionados
git ls-files | grep -E "\.(csv|json|txt)$"
# Output esperado: apenas *.example.csv
```

## 🏗️ Arquitetura do Projeto

### Estrutura Padrão dos Scripts

```bash
#!/bin/bash

# Metadados obrigatórios
# Author: endersonmenezes
# Date: YYYY-MM-DD
# Description: Breve descrição da funcionalidade
# CSV Format: formato_esperado_do_arquivo_csv
# Usage: bash script-name.sh [parametros]

# Importar funções compartilhadas
source functions.sh

# Validação de pré-requisitos
check_prerequisites() {
    is_gh_installed || exit 1
    # Outras validações necessárias
}

# Função principal
main() {
    echo "Iniciando $(basename "$0")..."
    
    # Lógica do script
    
    echo "Script concluído com sucesso."
}

# Executar apenas se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### Convenções de Nomenclatura

- **Scripts**: `NN-descricao-funcionalidade.sh` (NN = número sequencial)
- **CSVs de exemplo**: `NN-descricao-funcionalidade.example.csv`
- **CSVs de dados reais**: `NN-descricao-funcionalidade.csv` (gitignored)

### Funções Compartilhadas (`functions.sh`)

```bash
# Funções disponíveis:
is_gh_installed()           # Verifica GitHub CLI
audit_file()               # Gera hash de auditoria
read_config_file()         # Lê arquivo CSV de configuração
print_status()             # Output padronizado para stderr
```

## 🛠️ Padrões de Desenvolvimento

### 1. **Gerenciamento de Input/Output**

```bash
# ✅ CORRETO: Separar debug/status de output de dados
print_status "Processando organização: $org" >&2  # stderr
echo "$org,$repo_count"                          # stdout

# ❌ ERRADO: Misturar debug com dados
echo "Processando: $org - Encontrados: $repo_count"
```

### 2. **Tratamento de Erros**

```bash
# Sempre verificar comandos críticos
if ! gh repo list "$org" > /dev/null 2>&1; then
    print_status "ERRO: Não foi possível acessar organização $org" >&2
    continue
fi

# Rate limiting do GitHub
sleep 1  # Evitar rate limit entre chamadas de API
```

### 3. **Documentação no Script**

```bash
# Cabeçalho completo obrigatório:
# Author: endersonmenezes  
# Date: 2025-08-29
# Description: Busca PRs mergeados diariamente em múltiplas organizações
# CSV Format: organization
# Usage: bash 30-pr-daily-search.sh [YYYY-MM-DD]
# Dependencies: GitHub CLI, jq, functions.sh
# Output: CSV com formato date,org,repo,pr_number,pr_title,author,url
```

### 4. **Validação de Parâmetros**

```bash
validate_date() {
    local date="$1"
    if ! date -d "$date" >/dev/null 2>&1; then
        echo "ERRO: Data inválida '$date'. Use formato YYYY-MM-DD" >&2
        return 1
    fi
}
```

### 5. **Estrutura CSV Consistente**

```bash
# Sempre incluir cabeçalho
echo "date,organization,repository,pr_number,title,author,url"

# Escape adequado para CSV
echo "\"$date\",\"$org\",\"$repo\",\"$pr_number\",\"$title\",\"$author\",\"$url\""
```

## 📊 Scripts Existentes - Referência

### Gerenciamento de Equipes
- `01-add-team-as-admin.sh` - Adiciona equipes como admin
- `07-delete-teams.sh` - Remove equipes
- `14-remove-all-admin-to-write.sh` - Rebaixa permissões

### Gerenciamento de Repositórios  
- `02-archive-repos.sh` - Arquiva repositórios
- `18-delete-repo-sizeless.sh` - Deleta repos pequenos
- `25-close-security-alerts-archived-repos.sh` - Limpa alertas

### Análise e Auditoria
- `13-audit-repos.sh` - Auditoria de repositórios
- `27-github-contribs.sh` - Estatísticas de contribuição
- `28-go-dependencies-audit.sh` - Auditoria de dependências Go
- `30-pr-daily-search.sh` - Busca PRs diários ⭐ **MAIS RECENTE**

### Utilitários
- `26-search-and-replace.sh` - Busca e substitui código
- `29-download-wiki.sh` - Download de wikis
- `functions.sh` - Funções compartilhadas

## 🐛 Debugging e Troubleshooting

### Problemas Comuns

1. **Rate Limiting do GitHub**
   ```bash
   # Solução: Adicionar delays
   sleep 1
   ```

2. **Mistura de stdout/stderr**
   ```bash
   # Problema: Função retorna valor + debug
   print_status "Debug info"     # ❌ stdout
   
   # Solução: Redirecionar para stderr  
   print_status "Debug info" >&2 # ✅ stderr
   ```

3. **CSV mal formatado**
   ```bash
   # Problema: Caracteres especiais quebram CSV
   echo "$title"                 # ❌ pode ter vírgulas
   
   # Solução: Escape adequado
   echo "\"$title\""             # ✅ quoted
   ```

### Tools de Debug

```bash
# Verificar output do script
./script.sh > output.csv 2> debug.log

# Testar parsing de CSV
head -5 output.csv | csvlook  # Se disponível

# Verificar rate limit
gh api rate_limit
```

## ✅ Checklist de Desenvolvimento

Antes de qualquer commit ou push:

- [ ] **Segurança**: Nenhum dado sensível no Git
- [ ] **Documentação**: Cabeçalho completo no script  
- [ ] **Nomenclatura**: Seguir padrão `NN-descricao.sh`
- [ ] **CSV Example**: Criar arquivo `.example.csv` correspondente
- [ ] **Error Handling**: Validação adequada de parâmetros
- [ ] **Output Clean**: Separar debug (stderr) de dados (stdout)
- [ ] **README Update**: Documentar novo script no README.md
- [ ] **Teste**: Validar funcionamento com dados reais (local)

## 🚀 Workflow de Contribuição

### Para AIs desenvolvendo:

1. **Analisar contexto**: Entender o padrão dos scripts existentes
2. **Seguir templates**: Usar estrutura padrão estabelecida  
3. **Criar examples**: Sempre incluir arquivo `.example.csv`
4. **Testar localmente**: Pedir ao usuário para testar com dados reais
5. **Documentar**: Atualizar README.md com novo script
6. **Verificar segurança**: Confirmar que apenas código é commitado

### Para usuários:

1. **Criar CSV**: Copiar `.example.csv` e preencher com dados reais
2. **Executar**: `bash NN-script-name.sh [parâmetros]`
3. **Verificar output**: Conferir arquivos de resultado
4. **Limpar**: Dados sensíveis ficam apenas locais

## 📝 Exemplo Prático - Novo Script

```bash
#!/bin/bash
# Author: endersonmenezes
# Date: 2025-08-29  
# Description: Lista issues abertas por organização
# CSV Format: organization
# Usage: bash 31-list-open-issues.sh
# Dependencies: GitHub CLI, jq, functions.sh
# Output: CSV com formato org,repo,issue_number,title,author,created_at

source functions.sh

main() {
    check_prerequisites
    
    print_status "Iniciando busca de issues abertas..." >&2
    
    echo "organization,repository,issue_number,title,author,created_at"
    
    while IFS=',' read -r org; do
        [[ "$org" =~ ^[[:space:]]*$ ]] && continue
        [[ "$org" =~ ^#.*$ ]] && continue
        
        print_status "Processando organização: $org" >&2
        
        gh issue list --repo "$org" --state open --json number,title,author,createdAt,repository | \
            jq -r --arg org "$org" '.[] | [
                $org,
                .repository.name,
                .number,
                .title,
                .author.login,
                .createdAt
            ] | @csv'
        
        sleep 1  # Rate limiting
        
    done < "31-list-open-issues.csv"
    
    print_status "Busca concluída!" >&2
}

check_prerequisites() {
    is_gh_installed || exit 1
    [[ -f "31-list-open-issues.csv" ]] || {
        echo "ERRO: Arquivo 31-list-open-issues.csv não encontrado" >&2
        echo "Crie baseado no arquivo .example.csv" >&2
        exit 1
    }
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

## 🎯 Objetivos do Repositório

- **Automação**: Reduzir tarefas manuais repetitivas
- **Escala**: Gerenciar múltiplas organizações simultaneamente  
- **Auditoria**: Rastreabilidade e histórico de ações
- **Segurança**: Proteger informações confidenciais
- **Reutilização**: Código modular e documentado

---

**Última atualização**: 2025-08-29  
**Mantenedor**: endersonmenezes  
**Status**: Ativo ✅