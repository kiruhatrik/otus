apt update #обновление пакетов
apt install zfsutils-linux № установка zfs
zpool create storage1 mirror /dev/sdb /dev/sdc #создаем pool в миррор
zpool create storage2 mirror /dev/sdd /dev/sde
zpool create storage3 mirror /dev/sdf /dev/sdg
zpool create storage4 mirror /dev/sdh /dev/sdi
zfs create -o compression=gzip storage1/otus1   # создаем сразу с настройкой партицию
zfs create -o compression=zle storage2/otus2
zfs create -o compression=lzjb storage3/otus3
zfs create -o compression=lz4 storage4/otus4
for i in {1..4}; do wget -P /storage$i/otus$i https://gutenberg.org/cache/epub/2600/pg2600.converter.log; done # скачиваем на все партиции файл из доки 
zfs get compression,compressratio storage1/otus1 storage2/otus2 storage3/otus3 storage4/otus4
#NAME            PROPERTY       VALUE           SOURCE
#storage1/otus1  compression    gzip            local
#storage1/otus1  compressratio  3.64x           -
#storage2/otus2  compression    zle             local
#storage2/otus2  compressratio  1.00x           -
#storage3/otus3  compression    lzjb            local
#storage3/otus3  compressratio  1.82x           -
#storage4/otus4  compression    lz4             local
#storage4/otus4  compressratio  2.23x    
#Таким образом мы можем увидеть что файл был лучше всего сжат gzip

wget -O archive.tar.gz --no-check-certificate 'https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download' 

tar -xzvf archive.tar.gz
zpool import -d zpoolexport/
zpool import -d zpoolexport/ otus newotus
zfs get checksum newotus # проверка чек суммы у нас выдало sha256
zfs list newotus - проверка сколько места 
zpool status newotus - проверка какой тип pool у нас mirror
zfs get recordsize newotus - проверка recordsize у нас это 128К
zfs get compression newotus - проверка сжатия у нас это zle

wget -O otus_task2.file --no-check-certificate 'https://drive.usercontent.google.com/download?id=1wgxjih8YZ-cqLqaZVa0lA3h3Y029c3oI&export=download'

zfs receive newotus/test@today < otus_task2.file 

find /newotus/test -name "secret_message" # ищем файл secret_message внутри восстановленного датасета
#/newotus/test/task1/file_mess/secret_message
cat /newotus/test/task1/file_mess/secret_message
#https://otus.ru/lessons/linux-hl/