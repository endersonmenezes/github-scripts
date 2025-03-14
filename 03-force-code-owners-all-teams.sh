#!/usr/bin/env bash

###############################################################################
# Script para Verificar Aprovações de Pull Request conforme CODEOWNERS
#
# Autor: Enderson Menezes
# Criado: 2024-03-08
# Última atualização: 2024-03-08
#
# Descrição:
#   Este script verifica se um Pull Request recebeu as aprovações necessárias
#   de acordo com as regras definidas no arquivo CODEOWNERS do repositório.
#   Ele identifica os arquivos alterados no PR, determina quais times precisam
#   aprovar com base no CODEOWNERS e verifica se já existem aprovações desses times.
#
# Formato do CSV:
#   - Sem cabeçalho
#   - Formato: owner,repository,pr_number
#
# Uso: bash 03-force-code-owners-all-teams.sh
###############################################################################

# Carrega funções comuns
source functions.sh

# Verifica se o GitHub CLI está instalado
is_gh_installed

# Cria um SHA256 do arquivo para auditoria (Define variável SHA256)
audit_file

# Lê arquivo CSV de configuração (Define variável FILE)
read_config_file

# Extrai informações do PR do arquivo CSV
OWNER=$(cat $FILE | cut -d',' -f1)
REPOSITORY=$(cat $FILE | cut -d',' -f2)
PR_NUMBER=$(cat $FILE | cut -d',' -f3)
PR_URL="https://github.com/$OWNER/$REPOSITORY/pull/$PR_NUMBER"

# Obtém arquivos alterados no PR
echo "Obtendo arquivos alterados no PR #$PR_NUMBER..."
gh pr diff --name-only $PR_URL > changed_files.txt
echo 
echo "Arquivos alterados:"
cat changed_files.txt

# Adiciona uma barra no início de cada linha para compatibilidade com o formato CODEOWNERS
echo "Formatando nomes de arquivos para comparação com CODEOWNERS..."
sed -i 's/^/\//' changed_files.txt

# Verifica se o arquivo CODEOWNERS existe
CODEOWNERS_FILE=".github/CODEOWNERS"
if [ ! -f "$CODEOWNERS_FILE" ]; then
    echo "Arquivo CODEOWNERS não encontrado"
    exit 1
fi

# Verifica se o CODEOWNERS termina com uma linha em branco
if [ ! -z "$(tail -c 1 $CODEOWNERS_FILE)" ]; then
    echo "O arquivo CODEOWNERS deve ter uma linha em branco no final"
    # Adiciona uma linha em branco no final do arquivo
    echo "" >> $CODEOWNERS_FILE
fi

# Dicionário associativo para armazenar diretórios/arquivos protegidos e seus proprietários
declare -A SET_FILE_OR_DIR_AND_OWNER

# Lê o arquivo CODEOWNERS linha por linha
echo "Analisando regras do arquivo CODEOWNERS..."
while IFS= read -r line; do
    # Ignora comentários, linhas vazias e regras com "*" (global)
    if [[ "$line" =~ ^\s*# ]] || [[ "$line" =~ ^\s*$ ]] || [[ "$line" =~ ^\s*\* ]]; then
        continue
    fi
    LINE_ARRAY=($line)

    # Obtém o diretório ou arquivo e os proprietários
    DIR_OR_FILE=${LINE_ARRAY[0]}

    # Adiciona ao dicionário associativo
    SET_FILE_OR_DIR_AND_OWNER["$DIR_OR_FILE"]=${LINE_ARRAY[@]:1}
done < "$CODEOWNERS_FILE"

# Verifica se os arquivos alterados estão nos diretórios ou arquivos do CODEOWNERS
echo "Verificando arquivos modificados contra regras do CODEOWNERS..."
NECESSARY_APPROVALS=()
for FILE in $(cat changed_files.txt); do
    for DIR_OR_FILE in "${!SET_FILE_OR_DIR_AND_OWNER[@]}"; do
        # Compara se o arquivo está na árvore de pastas protegidas
        if [[ "$FILE" == *"$DIR_OR_FILE"* ]]; then
            echo 
            echo "ARQUIVO: $FILE está no CODEOWNERS"
            echo "PROPRIETÁRIOS: ${SET_FILE_OR_DIR_AND_OWNER[$DIR_OR_FILE]}"
            NECESSARY_APPROVALS+=(${SET_FILE_OR_DIR_AND_OWNER[$DIR_OR_FILE]})
        fi
    done
done

# Remove duplicatas da lista de aprovações necessárias
NECESSARY_APPROVALS=($(echo "${NECESSARY_APPROVALS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# Exibe as aprovações necessárias identificadas
echo
echo "Identificamos que os seguintes proprietários precisam aprovar o PR:"
for OWNER_APPROVAL in "${NECESSARY_APPROVALS[@]}"; do
    echo $OWNER_APPROVAL
done

# Obtém as aprovações atuais do PR
echo "Verificando aprovações existentes no PR..."
PR_APPROVED=$(gh pr view $PR_URL --json reviews | jq '.reviews[] | select(.state == "APPROVED") | .author.login')
PR_APPROVED=$(echo $PR_APPROVED | tr -d '"')

# Para cada proprietário necessário, verifica os membros da equipe
echo "Obtendo membros das equipes necessárias..."
echo 
for NECESSARY_OWNER in "${NECESSARY_APPROVALS[@]}"; do
    # Se o proprietário é uma equipe, verifica se a aprovação é de um membro da equipe
    # Formato: @org/team
    OWNER_ORGANIZATION=$(echo $NECESSARY_OWNER | cut -d'/' -f1)
    OWNER_ORGANIZATION=$(echo $OWNER_ORGANIZATION | cut -c 2-) # Remove o @ inicial
    OWNER_TEAM=$(echo $NECESSARY_OWNER | cut -d'/' -f2)
    API_CALL="/orgs/$OWNER_ORGANIZATION/teams/$OWNER_TEAM/members"
    MEMBER_LIST=$(gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        $API_CALL | jq '.[].login' | tr -d '"')
    echo $MEMBER_LIST > member_list_$OWNER_TEAM.txt
done

# Processa aprovações e verifica equipes aprovadas
echo 
MEMBER_LIST_FILES=$(ls member_list_*.txt)
TEAMS_APPROVED=()
TEAMS_MISSING_APPROVAL=()
echo "Verificando aprovações recebidas:"
for OWNER in $PR_APPROVED; do
    for MEMBER_LIST_FILE in $MEMBER_LIST_FILES; do
        TEAM=$(echo $MEMBER_LIST_FILE | cut -d'_' -f3 | cut -d'.' -f1)
        if grep -q $OWNER $MEMBER_LIST_FILE; then
            echo "$OWNER é membro da equipe $TEAM"
            # Evita duplicatas
            if [[ " ${TEAMS_APPROVED[@]} " =~ " ${TEAM} " ]]; then
                continue
            fi
            TEAMS_APPROVED+=($TEAM)
        fi
    done
done

# Compara as aprovações necessárias com as aprovações recebidas
echo "Comparando aprovações necessárias com aprovações recebidas..."
for NECESSARY_OWNER in "${NECESSARY_APPROVALS[@]}"; do
    OWNER_ORGANIZATION=$(echo $NECESSARY_OWNER | cut -d'/' -f1)
    OWNER_ORGANIZATION=$(echo $OWNER_ORGANIZATION | cut -c 2-) # Remove o @ inicial
    OWNER_TEAM=$(echo $NECESSARY_OWNER | cut -d'/' -f2)
    # Se a equipe já aprovou, pule
    if [[ " ${TEAMS_APPROVED[@]} " =~ " ${OWNER_TEAM} " ]]; then
        continue
    fi
    # Caso contrário, adicione à lista de equipes com aprovação pendente
    TEAMS_MISSING_APPROVAL+=($NECESSARY_OWNER)
done

# Exibe a conclusão da análise
echo 
echo "Equipes que aprovaram o PR:"
for TEAM in "${TEAMS_APPROVED[@]}"; do
    echo $TEAM
done
echo 
echo "Equipes com aprovação pendente:"
for TEAM in "${TEAMS_MISSING_APPROVAL[@]}"; do
    echo $TEAM
done

