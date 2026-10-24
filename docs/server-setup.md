# Конфигурация сервера devops-vm

Документ описывает конфигурацию учебного узла `devops-vm` и позволяет восстановить её
с нуля после отката на снимок `01-clean-install`. Все команды выполняются на сервере
от имени учётной записи `devops`, если не указано иное.

## 1. Общие сведения

| Параметр | Значение |
|---|---|
| Гипервизор | VirtualBox 7.x, гостевая система Ubuntu Server 26.04 LTS |
| Имя узла | `devops-vm` |
| Учётная запись администратора | `devops` (входит в группу `sudo`) |
| Сетевой адаптер 1 | NAT, проброс `127.0.0.1:2222` → `22` |
| Сетевой адаптер 2 | Host-only `192.168.56.102/24` |

## 2. Учётные записи и разграничение привилегий

Создание учётной записи и включение её в группу `sudo`:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
```

Постоянная работа от имени `root` не допускается; повышение привилегий выполняется
командой `sudo`, конфигурация `sudoers` редактируется только через `visudo`.

## 3. Доступ по SSH

Дополняющий файл конфигурации `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
```

Ключевой материал: `~/.ssh` — права `700`, `~/.ssh/authorized_keys` и закрытый ключ —
`600`. Клиентская конфигурация `~/.ssh/config` на хостовой системе:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Восстановление доступа: открытый ключ хостовой системы добавляется в
`~/.ssh/authorized_keys`, после чего проверяется вход командой `ssh devops`.

## 4. Межсетевой экран

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
```

Правило `limit` блокирует источник, открывший шесть и более соединений за 30 секунд.

## 5. Локальное доменное имя

На хостовой системе в файл `C:\Windows\System32\drivers\etc\hosts` (или `/etc/hosts`)
внесена запись:

```
192.168.56.102 devops.local
```

Полное доменное имя узла задано командой
`sudo hostnamectl set-hostname devops-vm` и записью в `/etc/hosts`:
`127.0.1.1 devops-vm devops.local`.

## 6. Доставка содержимого

Каталог ресурса `/var/www/devops-site` принадлежит `devops:devops`, права `755`;
файлы — `644`. Доставка выполняется сценарием `scripts/deploy.sh` (rsync через SSH,
`--chmod=D755,F644`, `--delete`), проверка доступности — `curl` с проверкой сертификата.

## 7. Снимки состояния

`01-clean-install`, `02-keys-configured`, `03-ssh-hardened`, `04-nginx-https`,
`05-docker-compose`, `06-before-kr2`, `07-kr2`.

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` из репозитория Ubuntu (1.28.3) |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site` |
| Активация | символическая ссылка в `/etc/nginx/sites-enabled/`, стандартный ресурс удалён |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталог `755`, файлы `644` |
| Сертификат | `/etc/ssl/certs/devops.crt`, права `644`, владелец `root` |
| Закрытый ключ | `/etc/ssl/private/devops.key`, права `600`, владелец `root` |
| Срок действия сертификата | 365 дней с даты выпуска |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |

Команда формирования самоподписанного сертификата с полем SAN:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Конфигурация ресурса: блок перенаправления `80 → 443` и блок `443 ssl` с директивами
`root`, `index`, `try_files`, `error_page 404 /404.html` и отдельными журналами.
Применение изменений: `sudo nginx -t && sudo systemctl reload nginx`.

Сертификат предъявляется клиенту как доверенный через `curl --cacert ~/devops.crt`;
в браузере самоподписанный сертификат принимается вручную либо импортируется в
хранилище доверенных сертификатов.
