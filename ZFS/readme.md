

## Стенд

- Ubuntu 24.04 (Vagrant + VirtualBox)
- 8 дополнительных дисков по 1024 MB (`/dev/sdb` – `/dev/sdi`)
- Полная автоматизация через `Vagrantfile` (см. в репозитории)

Поднять стенд:

```bash
vagrant up
```

---

## Задание 1. Алгоритм с наилучшим сжатием

**Текст задания:** определить, какие алгоритмы сжатия поддерживает ZFS (gzip, zle, lzjb, lz4), создать 4 файловые системы, на каждой применить свой алгоритм, сравнить сжатие одного и того же файла.

### Команды

```bash
apt update
apt install -y zfsutils-linux

# создаём 4 отдельных pool в режиме mirror (RAID1)
zpool create storage1 mirror /dev/sdb /dev/sdc
zpool create storage2 mirror /dev/sdd /dev/sde
zpool create storage3 mirror /dev/sdf /dev/sdg
zpool create storage4 mirror /dev/sdh /dev/sdi

# создаём датасет сразу с нужным алгоритмом сжатия
zfs create -o compression=gzip storage1/otus1
zfs create -o compression=zle   storage2/otus2
zfs create -o compression=lzjb  storage3/otus3
zfs create -o compression=lz4   storage4/otus4

# скачиваем один и тот же файл во все датасеты
for i in {1..4}; do
  wget -P /storage$i/otus$i https://gutenberg.org/cache/epub/2600/pg2600.converter.log
done

# сравниваем сжатие
zfs get compression,compressratio storage1/otus1 storage2/otus2 storage3/otus3 storage4/otus4
```

### Вывод

```
NAME             PROPERTY       VALUE   SOURCE
storage1/otus1   compression    gzip    local
storage1/otus1   compressratio  3.64x   -
storage2/otus2   compression    zle     local
storage2/otus2   compressratio  1.00x   -
storage3/otus3   compression    lzjb    local
storage3/otus3   compressratio  1.82x   -
storage4/otus4   compression    lz4     local
storage4/otus4   compressratio  2.23x   -
```

**Итог:** лучше всего файл сжал **gzip** (3.64x). Худший результат — **zle** (1.00x, фактически без сжатия), так как этот алгоритм сжимает только длинные последовательности нулевых байт, а текстовый файл их почти не содержит.

---

## Задание 2. Определение настроек пула

**Текст задания:** с помощью `zpool import` собрать pool ZFS из готового архива, определить его размер, тип, `recordsize`, используемое сжатие и контрольную сумму.

### Команды

```bash
# скачиваем архив с готовым pool (файлы filea/fileb используются как виртуальные диски)
wget -O archive.tar.gz --no-check-certificate \
  'https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download'
tar -xzvf archive.tar.gz

# смотрим, что можно импортировать (без подключения)
zpool import -d zpoolexport/

# импортируем под именем newotus (чтобы не конфликтовать с уже существующим otus)
zpool import -d zpoolexport/ otus newotus

# определяем настройки пула
zfs get checksum newotus
zfs list newotus
zpool status newotus
zfs get recordsize newotus
zfs get compression newotus
```

### Вывод

```
NAME     PROPERTY  VALUE      SOURCE
newotus  checksum  sha256     local

NAME     USED  AVAIL  REFER  MOUNTPOINT
newotus  2.04M  350M    24K  /newotus

  pool: newotus
 state: ONLINE
config:
        NAME        STATE     READ WRITE CKSUM
        newotus     ONLINE       0     0     0
          mirror-0  ONLINE       0     0     0
            filea   ONLINE       0     0     0
            fileb   ONLINE       0     0     0

NAME     PROPERTY    VALUE  SOURCE
newotus  recordsize  128K   local

NAME     PROPERTY     VALUE  SOURCE
newotus  compression  zle    local
```

**Итог:**

| Параметр | Значение |
|---|---|
| Размер | 480M (доступно 350M) |
| Тип pool | mirror (RAID1), собран из файлов, а не физических дисков |
| recordsize | 128K |
| Сжатие | zle |
| Контрольная сумма | sha256 |

---

## Задание 3. Работа со снапшотами

**Текст задания:** скопировать файл из удалённой директории, восстановить его локально через `zfs receive`, найти зашифрованное сообщение в файле `secret_message`.

### Команды

```bash
# скачиваем поток снапшота, подготовленный заранее (zfs send на стороне преподавателя)
wget -O otus_task2.file --no-check-certificate \
  'https://drive.usercontent.google.com/download?id=1wgxjih8YZ-cqLqaZVa0lA3h3Y029c3oI&export=download'

# восстанавливаем датасет newotus/test из этого потока
zfs receive newotus/test@today < otus_task2.file

# ищем файл secret_message внутри восстановленного датасета
find /newotus/test -name "secret_message"

# смотрим содержимое
cat /newotus/test/task1/file_mess/secret_message
```

### Вывод

```
/newotus/test/task1/file_mess/secret_message

https://otus.ru/lessons/linux-hl/
```

---

## Особенности проектирования и реализации

- Все 4 pool в задании 1 сделаны в режиме **mirror** (RAID1) для отказоустойчивости, хотя для чистого теста сжатия избыточность не обязательна — сделано по аналогии с примером из методички.
- Pool из задания 2 назван **newotus**, а не `otus`, так как имя `otus` может конфликтовать с уже существующим pool в системе — `zpool import` поддерживает переименование прямо при импорте: `zpool import -d <dir> <старое_имя> <новое_имя>`.
- `zpool import -d папка/` и `zfs receive < файл` — принципиально разные механизмы:
  - `zpool import -d` подключает уже готовый, полностью сформированный pool (файлы `filea`/`fileb` содержат полную структуру ZFS, как виртуальные диски).
  - `zfs receive` разворачивает **поток данных**, созданный командой `zfs send` на другой машине, и создаёт из него новый датасет с нуля.
- Вся настройка стенда автоматизирована через `Vagrantfile` — `vagrant up` разворачивает диски и выполняет все команды заданий 1–3 последовательно, без ручного вмешательства.

## Заметки

- Сжатие применяется только к файлам, записанным **после** включения свойства `compression` — файлы, скачанные до этого, останутся несжатыми.
- Название команды `zfs import` в тексте задания — опечатка методички; фактическая команда — `zpool import` (импорт пулов, а не файловых систем).