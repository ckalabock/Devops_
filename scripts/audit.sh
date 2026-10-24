#!/usr/bin/env bash
# Сценарий контроля конфигурации сервера devops-vm.
# Запуск: scripts/audit.sh   Код возврата 0 — все проверки пройдены, 1 — есть нарушения.
set -uo pipefail

FAILED=0

check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '[ OK ] %s\n' "$desc"
    else
        printf '[FAIL] %s\n' "$desc"
        FAILED=$((FAILED + 1))
    fi
}

echo '[1] Доступ по SSH'
check 'вход от имени root запрещён' \
    bash -c "sudo -n sshd -T | grep -qx 'permitrootlogin no'"
check 'парольная аутентификация отключена' \
    bash -c "sudo -n sshd -T | grep -qx 'passwordauthentication no'"
check 'служба SSH принимает соединения на порту 2222' \
    bash -c "sudo -n ss -tln | grep -q ':2222 '"
check 'права каталога ~/.ssh равны 700' \
    bash -c "test \"\$(stat -c '%a' ~/.ssh)\" = 700"

echo '[2] Межсетевой экран'
check 'ufw активен' \
    bash -c "sudo -n ufw status | grep -q 'Status: active'"
check 'политика по умолчанию deny incoming' \
    bash -c "sudo -n ufw status verbose | grep -q 'Default: deny (incoming)'"
check 'для порта 2222 действует правило limit' \
    bash -c "sudo -n ufw status | grep -Eq '^2222/tcp +(LIMIT|limit)'"

echo '[3] Имя узла'
check 'полное доменное имя узла devops.local' \
    bash -c "test \"\$(hostname -f)\" = devops.local"
check 'в /etc/hosts есть запись для devops.local' \
    bash -c "grep -q 'devops.local' /etc/hosts"

echo '[4] Веб-сервер'
check 'служба nginx активна' \
    bash -c "systemctl is-active --quiet nginx"
check 'конфигурация nginx синтаксически корректна' \
    bash -c "sudo -n nginx -t"
check 'сертификат действует не менее 30 дней' \
    bash -c "openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt"
check 'в каталоге ресурса нет файлов с правом записи для всех' \
    bash -c "test -z \"\$(find /var/www/devops-site -perm -o+w)\""
check 'права закрытого ключа TLS равны 600' \
    bash -c "test \"\$(sudo -n stat -c '%a' /etc/ssl/private/devops.key)\" = 600"

echo '[5] Контейнеризация'
check 'служба docker активна' \
    bash -c "systemctl is-active --quiet docker"
check 'контейнер СУБД находится в состоянии healthy' \
    bash -c "test \"\$(docker inspect -f '{{.State.Health.Status}}' app-db-1)\" = healthy"
check 'порты 5000 и 5432 не прослушиваются вне 127.0.0.1' \
    bash -c "test -z \"\$(ss -tln | awk '{print \$4}' | grep -E ':(5000|5432)\$' | grep -v '^127.0.0.1:')\""
check 'права файла ~/app/.env равны 600' \
    bash -c "test \"\$(stat -c '%a' ~/app/.env)\" = 600"

echo
if [ "$FAILED" -eq 0 ]; then
    echo 'Все проверки пройдены.'
    exit 0
fi
echo "Проверок не пройдено: $FAILED"
exit 1
