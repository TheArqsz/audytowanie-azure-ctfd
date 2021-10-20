# Audytowanie
Repozytorium na projekt z kursu Audytowanie na 2 semestrze studiów magisterskich CBE na PWr.

## CTFd - konfiguracja

Aby uruchomić CTFd jako usługę `ctfd` na maszynie bez dostępnej bazy danych:
```bash
HOST_IP=127.0.0.1 ./ctfd-setup.sh service create
```

Aby uruchomić CTFd jako usługę `ctfd` na maszynie z dostępną bazą danych:
```bash
HOST_IP=127.0.0.1 DATABASE_URI=xxx ./ctfd-setup.sh service nocreate
```

Aby uruchomić CTFd z poziomu konsoli na maszynie bez dostępnej bazy danych:
```bash
HOST_IP=127.0.0.1 ./ctfd-setup.sh manual create
```

Aby uruchomić CTFd z poziomu konsoli na maszynie bez dostępnej bazy danych:
```bash
HOST_IP=127.0.0.1 DATABASE_URI=xxx ./ctfd-setup.sh manual nocreate
```

W przypadku nieistniejącej bazy danych, stworzony zostanie kontener przechowujący dane w `/tmp/ctfd-mariadb-data`