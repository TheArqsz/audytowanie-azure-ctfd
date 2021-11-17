# Audytowanie
Repozytorium na projekt z kursu Audytowanie na 2 semestrze studiów magisterskich CBE na PWr.

## Lets Encrypt

Z Cloudflare pobieramy klucz API global i swój mail. W polu SSL ustawiamy `FULL`.

Zawartość `cloudflare.ini`
```ini
dns_cloudflare_api_key = APIKEY
dns_cloudflare_email = EMAIL
```

```bash
sudo apt install certbot python3-certbot-dns-cloudflare
sudo certbot certonly   --dns-cloudflare --dns-cloudflare-credentials cloudflare.ini -d DOMENA
```

Wygenerowany certyfikat podmieniamy w pliku `ctfd-setup.sh` we fragmencie o nginxie.

## Skrypt dla CTFd i nginxa

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
lub
```bash
./ctfd-setup.sh -m cli --database-user USER --database-pwd 'PASSWORD' --database-ip IP --nginx
```


W przypadku zmockowanej bazy danych, stworzony zostanie kontener przechowujący dane w `/tmp/ctfd-mariadb-data`
