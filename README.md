# GitHub Scripts

Conjunto de scripts para automatizar tarefas no GitHub e Azure DevOps. Esta coleção foi criada para facilitar operações comuns de gerenciamento em organizações e repositórios do GitHub, além de integração com Azure DevOps.

## Índice

- [Requisitos](#requisitos)
- [Como utilizar](#como-utilizar)
- [Estrutura comum](#estrutura-comum)
- [Funções compartilhadas](#funções-compartilhadas)
- [Scripts disponíveis](#scripts-disponíveis)
- [Documentação](#documentação)

## Requisitos

- [GitHub CLI](https://cli.github.com/) instalado e autenticado
- Bash (para a maioria dos scripts)
- Python 3 (para scripts específicos)
- jq (para processamento de JSON)
- Permissões adequadas no GitHub para as operações desejadas:
  - Para gerenciamento de repositórios: permissões de administrador nos repositórios
  - Para fechamento de alertas de segurança: permissões de administrador e acesso a alertas de segurança
  - Para operações em organizações: papel apropriado na organização

## Como utilizar

A maioria dos scripts segue um padrão de uso semelhante:

1. Crie um arquivo CSV com o mesmo nome do script (ex: `01-add-team-as-admin.csv` para o script `01-add-team-as-admin.sh`)
2. Preencha o arquivo CSV com os dados necessários seguindo o formato indicado na descrição do script
3. Execute o script:

```bash
bash nome-do-script.sh [parâmetros adicionais]
```

Para gravar a execução do script (opcional):

```bash
CASE="nome-do-caso"
terminalizer record $CASE
terminalizer render $CASE
```

## Estrutura comum

Todos os scripts compartilham características comuns:

- Utilizam um arquivo CSV com o mesmo nome como fonte de dados
- Implementam funções de auditoria para rastreabilidade
- Seguem um padrão de documentação consistente
- Fazem uso do GitHub CLI para operações de API

## Funções compartilhadas

O arquivo `functions.sh` contém funções comuns utilizadas pelos scripts:

- `is_gh_installed` - Verifica se o GitHub CLI está instalado
- `audit_file` - Gera um hash SHA256 para auditoria do estado atual do script
- `read_config_file` - Lê o arquivo de configuração CSV correspondente ao script

## Scripts disponíveis

### Gerenciamento de equipes e permissões

- **01-add-team-as-admin.sh**  
  Adiciona equipes como administradoras a um conjunto de repositórios.  
  _Formato do CSV: owner/repo,team,permission_

- **03-force-code-owners-all-teams.sh**  
  Verifica aprovações de Pull Request conforme regras do CODEOWNERS.  
  _Formato do CSV: owner,repository,pr_number_

- **07-delete-teams.sh**  
  Remove equipes específicas de uma organização.  
  _Formato do CSV: team,org_

- **08-organization-roles.sh**  
  Gerencia papéis personalizados em uma organização do GitHub.  
  _Uso: bash 08-organization-roles.sh <organização>_

- **14-remove-all-admin-to-write.sh**  
  Rebaixa permissões de equipes de administrador para escrita em repositórios.  
  _Uso: bash 14-remove-all-admin-to-write.sh <org> <team>_

### Gerenciamento de repositórios

- **02-archive-repos.sh**  
  Arquiva repositórios, tratando alertas de segurança e removendo acessos.  
  _Formato do CSV: owner/repo_

- **09-archive-or-delete-repo.sh**  
  Arquiva repositórios com conteúdo ou deleta repositórios vazios.  
  _Formato do CSV: repository_

- **11-if-archived-remove-all-access.sh**  
  Remove todos os acessos de repositórios arquivados em uma organização.  
  _Uso: bash 11-if-archived-remove-all-access.sh <organização>_

- **15-public-to-private-and-archive.sh**  
  Converte repositórios públicos para privados e os arquiva.  
  _Formato do CSV: organization,repository_

- **18-delete-repo-sizeless.sh**  
  Deleta repositórios com menos de 1MB de tamanho.  
  _Formato do CSV: owner/repo_

- **21-update-repo-properties.sh**  
  Atualiza propriedades personalizadas para repositórios do GitHub.  
  _Formato do CSV: owner/repo,property_key,property_value_

- **22-custom-properties-organization.sh**  
  Atualiza propriedades personalizadas para uma organização no GitHub.  
  _Formato do CSV: owner,name,value_type,required,default_value,description,allowed_values_

- **23-is-archived.sh**  
  Verifica se repositórios estão arquivados e salva os resultados em um CSV.  
  _Formato do CSV: owner/repo_

- **25-close-security-alerts-archived-repos.sh**  
  Processa repositórios arquivados para limpar alertas de segurança. Desarquiva temporariamente, fecha alertas do Dependabot e Code scanning, e arquiva novamente.  
  _Formato do CSV: organization,repository_

- **26-search-and-replace.sh**  
  Busca por padrões de código em repositórios do GitHub e aplica substituições usando regex. Cria pull requests automáticos com descrições detalhadas e gera arquivos de resultado.  
  
  **Formato do CSV:**
  ```csv
  query,search_pattern,replace_pattern,file_pattern,commit_message
  ```
  
  **Descrição das colunas:**
  - `query`: Query de busca do GitHub (ex: `org:stone-payments spot path:.github`, `repo:owner/name keyword`)
  - `search_pattern`: Padrão regex para buscar no conteúdo dos arquivos (ex: `runs-on: (.+)-spot`)
  - `replace_pattern`: Padrão de substituição com grupos de captura (ex: `runs-on: \1`)
  - `file_pattern`: Padrões de arquivo separados por `;` (ex: `*.yml;*.yaml;*.py`)
  - `commit_message`: Mensagem do commit e título do PR
  
  _Uso: bash 26-search-and-replace.sh [--dry-run] [--debug]_  
  _Funcionalidades: Busca por API, PRs automáticos, modo dry-run, output para arquivo_
  
  **Dicas importantes:**
  - Use `--dry-run` para testar antes de executar
  - Queries sem aspas funcionam melhor: `org:name keyword` em vez de `"org:name keyword"`
  - Padrões de arquivo usam `;` como separador: `*.yml;*.yaml`
  - Regex suporta grupos de captura: `(.+)` pode ser referenciado como `\1`

- **29-download-wiki.sh**  
  Baixa toda a Wiki de um repositório do GitHub em formato markdown.  
  _Uso: bash 29-download-wiki.sh <repository_url_or_name> [output_dir]_  
  
  **Exemplos de uso:**
  ```bash
  # Usando URL da wiki
  bash 29-download-wiki.sh https://github.com/dlpco/developers/wiki/
  
  # Usando nome do repositório
  bash 29-download-wiki.sh dlpco/developers
  
  # Especificando diretório de saída
  bash 29-download-wiki.sh dlpco/developers /tmp/my_wiki
  ```
  
  **Funcionalidades:**
  - Download via clone git (método preferido - mantém histórico)
  - Fallback via API do GitHub (para wikis que não permitem clone)
  - Criação automática de índice com lista de páginas
  - Verificação de dependências e autenticação
  - Relatório de estatísticas do download
  - Suporte a diferentes formatos de entrada (URL ou owner/repo)

### Análise e auditoria

- **05-list-repos-and-teams.sh**  
  Lista todos os repositórios e equipes de uma organização.  
  _Uso: bash 05-list-repos-and-teams.sh <organização>_

- **06-analyze-logs.py**  
  Converte arquivos JSONL para CSV para análise de logs.  
  _Uso: python 06-analyze-logs.py_

- **10-repo-activity.sh**  
  Gera relatório CSV de atividades em repositórios.  
  _Uso: bash 10-repo-activity.sh <organização> [debug] [random_page]_

- **12-list-public-repos.sh**  
  Lista todos os repositórios públicos para organizações especificadas.  
  _Uso: bash 12-list-public-repos.sh "organizações,separadas,por,vírgula"_

- **13-audit-repos.sh**  
  Audita repositórios baseado em informações de um arquivo CSV.  
  _Formato do CSV: owner,repo,query_prs_

- **16-query-github-repos.sh**  
  Pesquisa repositórios usando a API do GitHub e gera relatórios.  
  _Uso: bash 16-query-github-repos.sh "QUERY"_

- **17-github-new-audit-repo.sh**  
  Realiza auditoria detalhada de um repositório em um período específico.  
  _Uso: bash 17-github-new-audit-repo.sh REPO DATA_INICIO DATA_FIM_

- **19-collect-repo-info.sh**  
  Coleta informações detalhadas sobre configuração de repositórios.  
  _Uso: bash 19-collect-repo-info.sh <organização> <repositório>_

- **27-github-contribs.sh**  
  Coleta estatísticas de contribuidores de repositórios GitHub.  
  _Formato do CSV: reporsitory (owner/repo)_  
  _Uso: bash 27-github-contribs.sh [--test]_  
  
  **Funcionalidades:**
  - Extrai total de contribuições e lista de contribuidores
  - Paginação automática da API do GitHub
  - Modo de teste (apenas primeiros 10 repositórios)
  - Saída em CSV com formato: repo,total_contribs,contribs
  - Tratamento abrangente de erros e rastreamento de progresso

- **28-go-dependencies-audit.sh**  
  Audita repositórios Go e extrai dependências e estrutura do projeto.  
  _Uso: bash 28-go-dependencies-audit.sh <organization_name> [--test]_  
  
  **Funcionalidades:**
  - Análise de dependências a partir de arquivos go.mod
  - Análise de estrutura de projeto (pastas app, domain, extensions, gateways, proto, etc.)
  - Rastreamento de data do último commit
  - Modo de teste para validação
  - Saída em dois CSVs: dependencies e project structure
  - Paginação automática da API do GitHub

- **30-pr-daily-search.sh**  
  Busca PRs mergeados dia a dia em múltiplas organizações do GitHub.  
  _Formato do CSV: organization_  
  _Uso: bash 30-pr-daily-search.sh [DATA_INICIO] [DATA_FIM] [--test]_  
  
  **Funcionalidades:**
  - Busca por PRs mergeados em branches main/master
  - Período configurável (padrão: 2025-01-01 até hoje)
  - Modo de teste (apenas primeiros 3 dias)
  - Rate limiting inteligente para evitar limites da API
  - Saída em CSV com informações completas do PR
  - Usa 'gh search prs' para busca eficiente por organização
  - Progresso detalhado e estimativas de tempo
  - Tratamento robusto de erros e validação de datas

### Autenticação e integração

- **04-app-token.sh**  
  Gera tokens para aplicações GitHub usando credenciais fornecidas.  
  _Formato do CSV: owner,app_id,app_install_id,file_

### Azure DevOps

- **20-test-azure-devops-token.sh**  
  Testa a conectividade e autenticação com Azure DevOps, incluindo feeds NuGet.  
  _Uso: bash 20-test-azure-devops-token.sh <token> [organização] [projeto]_

- **24-azure-devops-pools-agents-envs.sh**  
  Escaneia uma organização do Azure DevOps e coleta informações sobre projetos, pools de agentes e ambientes.  
  _Uso: bash 24-azure-devops-pools-agents-envs.sh <token> <organização> [formato_saída]_

## Documentação

Cada script contém em seu cabeçalho:

- Nome e descrição
- Autor e datas de criação/atualização
- Formato do arquivo de entrada (quando aplicável)
- Instruções de uso
- Parâmetros e suas descrições

Para usar qualquer script, verifique primeiro seu conteúdo para entender completamente sua funcionalidade e requisitos.
