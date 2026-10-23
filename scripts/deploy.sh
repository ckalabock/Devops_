#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://192.168.56.102"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
elif [[ -n "${1:-}" ]]; then
    echo "Ошибка: неизвестный аргумент '$1'" >&2
    exit 1
fi

# 2. Требование 4: Проверка наличия index.html
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл ${LOCAL_DIR}index.html отсутствует!" >&2
    exit 1
fi

# 3. Требование 5: Проверка незафиксированных изменений в Git
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "Ошибка: в рабочей копии или индексе есть незафиксированные изменения!" >&2
    exit 1
fi

# 4. Требование 3, 8, 9: Синхронизация через rsync
rsync -avz --delete --chmod=D755,F644 \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    ${DRY_RUN} "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 5. При --dry-run завершение с кодом 0 без проверки доступности
if [[ -n "${DRY_RUN}" ]]; then
    echo "План операций выведен успешно (--dry-run). Изменения на сервере не производились."
    exit 0
fi

# 6. Требование 6: Проверка доступности ресурса по HTTPS
if ! curl -f -s --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен или не прошёл проверку сертификата!" >&2
    exit 1
fi

# 7. Требование 7: Успешное завершение с выводом короткого хеша коммита
COMMIT_HASH="$(git rev-parse --short HEAD)"
echo "Деплой успешно выполнен. Задеплоен коммит: ${COMMIT_HASH}"
exit 0
