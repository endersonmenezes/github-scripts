#!/usr/bin/env bash

###############################################################################
# Script para Adicionar Times como Administradores de Repositórios
#
# Autor: Enderson Menezes
# Criado: 2024-03-08
# Última atualização: 2025-03-14
#
# Descrição:
#   Este script lê um arquivo CSV de configuração com o formato:
#   "owner-repo,team,permission" e concede permissões de equipe nos repositórios.
#   Ele verifica se o repositório e a equipe existem e se você tem permissão
#   para acessá-los antes de atribuir as permissões.
#
# Formato do CSV:
#   - Linha de cabeçalho: owner-repo,team,permission
#   - Linhas de dados: organization/repo,team-name,permission
#   - Permissões válidas: pull, triage, push, maintain, admin
#
# Uso: bash 01-add-team-as-admin.sh
###############################################################################

# Carrega funções comuns do arquivo functions.sh
source functions.sh

# Verifica se o GitHub CLI está instalado
is_gh_installed

# Cria um SHA256 do arquivo para auditoria (Define variável SHA256)
audit_file

# Lê arquivo CSV de configuração (Define variável FILE)
read_config_file

# Verifica formato específico do arquivo de configuração
if [[ $(head -n 1 $FILE) != "owner-repo,team,permission" ]]; then
    echo "O arquivo $FILE não possui o formato correto."
    echo "O cabeçalho deve ser: owner-repo,team,permission"
    exit 1
fi

# Verifica se o arquivo termina com uma linha em branco
if [[ $(tail -n 1 $FILE) != "" ]]; then
    echo "O arquivo $FILE não possui uma linha em branco no final."
    echo "Adicionando linha em branco..."
    echo "" >> $FILE
fi

# Processa cada linha do arquivo CSV
while IFS=, read -r OWNER_REPO TEAM PERMISSION; do

    # Ignora a linha de cabeçalho
    [ "$OWNER_REPO" == "owner-repo" ] && continue

    # Ignora linhas em branco
    [ -z "$OWNER_REPO" ] && continue

    # Extrai o nome da organização e do repositório
    OWNER=$(echo $OWNER_REPO | cut -d'/' -f1)
    REPOSITORY=$(echo $OWNER_REPO | cut -d'/' -f2)

    # Verifica se o repositório existe e se o usuário tem permissão para acessá-lo
    echo "Verificando repositório ${OWNER_REPO}..."
    gh api repos/"${OWNER_REPO}" &>/dev/null || {
        echo "O repositório ${OWNER_REPO} não existe ou você não tem permissão para acessá-lo."
        exit 1
    }
    echo "O repositório ${OWNER_REPO} existe e você tem permissão para acessá-lo."

    # Verifica se a equipe existe
    echo "Verificando equipe ${TEAM}..."
    gh api orgs/"${OWNER}"/teams/"${TEAM}" &>/dev/null || {
        echo "A equipe ${TEAM} não existe ou você não tem permissão para acessá-la."
        exit 1
    }
    echo "A equipe ${TEAM} existe e você tem permissão para acessá-la."

    # Adiciona a equipe com a permissão especificada
    echo "Adicionando a equipe ${TEAM} como ${PERMISSION} no repositório ${OWNER_REPO}..."
    
    # Adiciona ou atualiza a permissão da equipe
    gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /orgs/"${OWNER}"/teams/"${TEAM}"/repos/"${OWNER}"/"${REPOSITORY}" \
        -f permission="${PERMISSION}" &>/dev/null || {
        echo "A equipe ${TEAM} não foi adicionada como ${PERMISSION} no repositório ${OWNER_REPO}."
        exit 1
    }
    echo "A equipe ${TEAM} foi adicionada como ${PERMISSION} no repositório ${OWNER_REPO}."
done < $FILE

echo "Processo finalizado com sucesso!"
