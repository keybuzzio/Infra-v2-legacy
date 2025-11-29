#!/bin/bash
TSV_FILE=/opt/keybuzz-installer/servers.tsv
declare -a PROXYSQL_NODES=()
declare -a PROXYSQL_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${HOSTNAME}" == "proxysql-01" ]] || [[ "${HOSTNAME}" == "proxysql-02" ]]; then
        echo "DEBUG: HOSTNAME=[${HOSTNAME}] ROLE=[${ROLE}] SUBROLE=[${SUBROLE}] IP_PRIVEE=[${IP_PRIVEE}]"
    fi
    
    if [[ "${ROLE}" == "db_proxy" ]] || ([[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "proxysql" ]]); then
        if [[ "${HOSTNAME}" == "proxysql-01" ]] || [[ "${HOSTNAME}" == "proxysql-02" ]]; then
            if [[ -n "${IP_PRIVEE}" ]]; then
                PROXYSQL_NODES+=("${HOSTNAME}")
                PROXYSQL_IPS+=("${IP_PRIVEE}")
                echo "  -> Ajouté: ${HOSTNAME} (${IP_PRIVEE})"
            else
                echo "  -> IP_PRIVEE vide pour ${HOSTNAME}"
            fi
        fi
    fi
done
exec 3<&-

echo "Résultat final: ${PROXYSQL_NODES[*]} (${PROXYSQL_IPS[*]})"

