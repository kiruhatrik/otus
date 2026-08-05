# Конспект: RPM пакеты + свой репозиторий (RHEL/AlmaLinux)

## Три семейства Linux-пакетов

```
Debian/Ubuntu  → dpkg/apt, формат .deb
RHEL/AlmaLinux → rpm/yum(dnf), формат .rpm
Arch           → pacman, формат .pkg.tar.zst
```

dpkg и rpm — низкоуровневые утилиты (просто ставят конкретный файл).
apt и yum/dnf — надстройки, которые ещё и сами разрешают зависимости.

`yum update` в RHEL — это НЕ то же самое, что `apt update` в Ubuntu!
`yum update` = `apt upgrade` (реально обновляет систему).
Просто обновить список пакетов — `yum check-update`.

## Где лежат репозитории (конфиги, откуда качать пакеты)

```
Ubuntu: /etc/apt/sources.list.d/*.list
RHEL:   /etc/yum.repos.d/*.repo   (каждый репо — отдельный файл)
```

Пример .repo файла:
```ini
[myrepo]
name=My Local Repo
baseurl=http://localhost:8080/repo
gpgcheck=0
enabled=1
```

## Структура ~/rpmbuild (создаётся командой rpmdev-setuptree)

```
SOURCES/  → сюда САМ кладу архив с исходниками (.tar.gz)
SPECS/    → сюда САМ кладу .spec файл (рецепт сборки)
BUILD/    → сюда rpmbuild распаковывает архив и собирает (%build)
BUILDROOT/ → временная "песочница" — имитация корня / целевой системы,
             сюда %install кладёт файлы (через %{buildroot})
RPMS/     → готовый .rpm пакет
SRPMS/    → готовый .src.rpm (исходники + spec вместе, для пересборки)
```

Поток: я кладу в SOURCES+SPECS → rpmbuild работает в BUILD→BUILDROOT →
результат выходит в RPMS+SRPMS.

## Секции spec-файла

```
Name/Version/Release  → идентификация пакета
Source0                → имя архива из SOURCES/
%description             → описание (видно через rpm -qi)
%prep + %setup -q          → распаковать архив (макрос делает tar+cd сам)
%build                       → команды сборки (./configure && make)
%install                       → копирование файлов В %{buildroot}
%files                           → список файлов, БЕЗ %{buildroot} —
                                  реальные пути на целевой системе
%changelog                        → история версий
%check                              → (опционально) автотесты после сборки
```

`%{buildroot}` — RPM-макрос (не bash-переменная!), путь к временной
"песочнице". В %install работаем С ним, в %files — БЕЗ него.

## Основные команды

```bash
rpmdev-setuptree                    # создать структуру ~/rpmbuild
rpmbuild -ba имя.spec                # собрать И .rpm И .srpm
rpm -qip файл.rpm                     # метаданные пакета (без установки)
rpm -qlp файл.rpm                      # список файлов в пакете
yum localinstall -y файл.rpm            # установить локальный .rpm
rpm -qi имя_пакета                        # метаданные уже установленного
rpm -ql имя_пакета                          # файлы уже установленного пакета
rpm -e имя_пакета                             # удалить (чисто, только "свои" файлы)
```

## Работа с существующим пакетом (пересборка, как делали с Apache)

```bash
yumdownloader --source httpd          # скачать SRPM (исходники+spec)
rpm -Uvh httpd*.src.rpm                 # распаковать SRPM в SOURCES/SPECS
yum-builddep -y ~/rpmbuild/SPECS/httpd.spec  # поставить всё для сборки
```

Если чего-то не хватает для сборки — возможно нужно включить
дополнительный репозиторий с dev-пакетами:
```bash
yum config-manager --set-enabled crb   # CodeReady Builder — репо с -devel пакетами
yum install -y epel-release             # Extra Packages for Enterprise Linux
```

## Свой репозиторий — пошагово

```bash
mkdir -p /var/www/html/repo
cp мой-пакет.rpm /var/www/html/repo/
yum install -y createrepo_c
createrepo_c /var/www/html/repo/        # создаёт repodata/ (индекс метаданных)
```

Обновление репозитория при добавлении нового пакета:
```bash
cp новый-пакет.rpm /var/www/html/repo/
restorecon -Rv /var/www/html/repo/       # см. ниже про SELinux!
createrepo_c --update /var/www/html/repo/
```

## Раздача репозитория через Nginx

Конфиг в /etc/nginx/conf.d/repo.conf:
```nginx
server {
    listen 8080;
    server_name localhost;
    location /repo/ {
        root /var/www/html;
        autoindex on;    # без этого будет 403, а не список файлов
    }
}
```

```bash
nginx -t                                   # проверить конфиг перед запуском!
systemctl enable --now nginx
firewall-cmd --add-port=8080/tcp --permanent  # RHEL по умолчанию блокирует порты
firewall-cmd --reload
```

## ВАЖНО: SELinux — специфика RHEL, которой нет в Ubuntu

Даже если Unix-права (rwx) в порядке, SELinux может ДОПОЛНИТЕЛЬНО
блокировать доступ по "метке" (контексту) файла.

```bash
getenforce                        # Enforcing = SELinux активен и блокирует
ls -Z /путь/                       # посмотреть текущие метки файлов
restorecon -Rv /путь/                # исправить метки на правильные для этого места
```

Файлы, скопированные из "чужого" места (например из ~/rpmbuild/RPMS/),
УНАСЛЕДУЮТ старую метку — после каждого cp в папку веб-сервера нужно
заново прогонять restorecon.

## Подключение своего репозитория к системе

```bash
cat > /etc/yum.repos.d/myrepo.repo << 'EOF'
[myrepo]
name=My Local Repo
baseurl=http://localhost:8080/repo
gpgcheck=0
enabled=1
EOF

yum repolist              # проверить что репо подключился
yum search имя_пакета       # найти пакет
yum install -y имя_пакета     # установить ИЗ СВОЕГО репозитория
```

## Репозиторий (yum) vs просто папка с файлами — разные вещи

- `.repo` файл работает ТОЛЬКО с yum/dnf и ТОЛЬКО с .rpm пакетами
- Nginx раздаёт ЛЮБЫЕ файлы из указанной папки, без разбора типа
- `wget`/`curl` скачивают что угодно по прямой ссылке — независимо
  от того, что написано в .repo файле (тот вообще не читается wget'ом)
- Поэтому картинки/архивы/документы лучше класть в ОТДЕЛЬНУЮ папку
  (например /files/, отдельный location в nginx), а не мешать
  с RPM-пакетами — просто для порядка, technически можно и вместе

## Личный вывод

В реальном проде пересборку готового ПО (Apache/Nginx) из исходников
делают редко — 95% случаев это просто `yum install готовый-пакет`.
Пересборка нужна, только если готового пакета нет, нужна кастомная
опция, или ты сам разработчик патча. Зато СВОИ внутренние пакеты
(как diskcheck) — это реально частая задача DevOps, чтобы раскатывать
единообразно на много серверов через обычный yum install, а не
руками копировать файлы через Ansible.

---

# Дополнение: DEB-пакеты (Debian/Ubuntu) — та же логика, другие инструменты

## Соответствие RPM ↔ DEB

```
RPM                              DEB
────────────────────────────────────────────────
~/rpmbuild/ (SOURCES+SPECS)       ~/имя-версия/ + debian/ ВНУТРИ неё
.spec (один файл, секции)           debian/control, rules, install, changelog
                                     (несколько отдельных файлов)
rpmbuild -ba                          dpkg-buildpackage -us -uc -b
createrepo_c                            dpkg-scanpackages
rpm -qip / rpm -qlp                       dpkg-deb -I / dpkg-deb -c
rpm -Uvh / yum localinstall                  dpkg -i
```

## Установка инструментов

```bash
sudo apt install -y build-essential debhelper devscripts dh-make
```

## Создание структуры пакета

```bash
mkdir -p ~/имя-1.0/usr/bin        # ВАЖНО: usr/bin, НЕ usr/local/bin!
# кладём файлы приложения...
cd ~/имя-1.0
dh_make --createorig -s -y -p имя_1.0
```

Это создаст папку `debian/` с шаблонами. Нужные файлы:

- **debian/control** — метаданные (имя, описание, зависимости) —
  аналог Name/Description/Requires из spec-файла
- **debian/rules** — обычно трогать НЕ нужно (там просто `dh $@`,
  debhelper сам всё делает по стандартной схеме)
- **debian/install** — куда класть файлы, формат:
  ```
  usr/bin/скрипт.sh    usr/bin
  ```
  (пути БЕЗ ведущего слэша!)
- **debian/changelog** — версия и дата, создаётся автоматически

## ВАЖНОЕ ОТЛИЧИЕ ОТ RPM — Debian строго следит за FHS

RPM спокойно разрешает класть файлы пакета в `/usr/local/bin/`.
Debian (через `dh_usrlocal`) это ЗАПРЕЩАЕТ — пакеты ДОЛЖНЫ класть
исполняемые файлы в `/usr/bin/`, а `/usr/local/` зарезервирован
только для ручных, неуправляемых пакетами файлов администратора.

Если увидишь ошибку `dh_usrlocal: error: ... is not a directory` —
это она самая, нужно переносить файлы в /usr/bin.

## Сборка и установка

```bash
dpkg-buildpackage -us -uc -b     # -us -uc = без GPG-подписи (не нужна для учебных целей)
                                    # результат появится ОДНИМ УРОВНЕМ ВЫШЕ (~/, не в папке проекта)

dpkg-deb -I файл.deb               # метаданные пакета
dpkg-deb -c файл.deb                 # список файлов внутри
sudo dpkg -i файл.deb                  # установить
```

## Свой DEB-репозиторий (аналог createrepo, но команда другая)

```bash
sudo apt install -y dpkg-dev
mkdir -p /var/www/html/repo
cp мой-пакет.deb /var/www/html/repo/
cd /var/www/html/repo
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
```

Дальше — раздача через Nginx точно так же, как с RPM (тот же location,
тот же принцип). Подключение репозитория на клиенте — через
`/etc/apt/sources.list.d/myrepo.list`:
```
deb [trusted=yes] http://localhost:8080/repo ./
```

## Главный вывод по итогам практики (RPM + DEB)

Архитектура ОДИНАКОВАЯ в обоих мирах:
```
Пакет (rpm/deb)  →  Метаданные (createrepo/dpkg-scanpackages)  →
    →  Веб-сервер раздаёт папку (Nginx)  →  Менеджер пакетов клиента (yum/apt)
```

Точный синтаксис control/rules/spec-файлов запоминать не обязательно —
это делается редко, и в реальной практике проще каждый раз свериться
с документацией/примером, чем держать в голове. Важно понимание
АРХИТЕКТУРЫ целиком: откуда берётся пакет, как формируется репозиторий,
как клиент его находит и устанавливает.