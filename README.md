# Audytowanie
Repozytorium na projekt z kursu Audytowanie na 2 semestrze studiów magisterskich CBE na PWr.

## Pomoc

```bash
Obowiązkowe argumenty:
   -m, --mode        				Tryb aplikacji (service lub cli)
   
Opcjonalne argumenty:
   -h, --help        				Wyświetl pomoc
   -d, --no-install-dependencies		Nie instaluj zależności
   Ustawienia bazy MySQL:
   --database-user        			Użytkownik bazy (domyślny: root)
   --database-pwd        			Hasło do bazy danych (domyślny: dbctfdpass)
   --database-ip        			Adres bazy danych (domyślny: localhost)
   --database-name        			Nazwa bazy danych (domyślny: ctfd)
   
   Alternatywnie, istnieje opcja ustawienia całego URL bazy danych (domyślny typ to mysql+pymysql)
   --database-url        			URL bazy (domyślny: "mysql+pymysql://root:dbctfdpass@localhost/ctfd")
   
   --mock-database        			Symuluj bazę danych (w kontenerze)
   --secret-key       				Klucz (secret key) do CTFd (domyślny: empty)
   --host-ip					IP hota CTFd (domyślny: 127.0.0.1)
   --host-port					Port hosta CTFd (domyślny: 8000)
   -u, --user					Użytkownik z jakim uruchomi się CTFd (domyślny: aktualny użytkownik)
   -n, --nginx					Zainstaluj nginx (proxy)
```

## CTFd - konfiguracja

Aby uruchomić CTFd (jako user `ctfd`) jako usługę `ctfd`, zmockować bazę i wygenerować proxy w nginx:
```bash
./ctfd-setup.sh -m service --mock-database -u ctfd --nginx
```

Aby uruchomić CTFd jako usługę `ctfd` z istniejącą bazą danych:
```bash
./ctfd-setup.sh -m service --mock-database -u ctfd --nginx --database-url "mysql+pymysql://root:example@localhost/ctfd"
```

Aby uruchomić CTFd z poziomu konsoli na maszynie i zmockować bazę:
```bash
./ctfd-setup.sh -m cli --mock-database -u ctfd 
```

Aby uruchomić CTFd z poziomu konsoli z istniejącą bazą danych:
```bash
./ctfd-setup.sh -m cli --mock-database -u ctfd --database-url "mysql+pymysql://root:example@localhost/ctfd"
```

W przypadku zmockowanej bazy danych, stworzony zostanie kontener przechowujący dane w `/tmp/ctfd-mariadb-data`
