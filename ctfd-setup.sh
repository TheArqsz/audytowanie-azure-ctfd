#!/usr/bin/env bash
# Quickly setup CTFd instance locally (as a service or as a process in the CLI)
#
# Copyright 2021 TheArqsz

set -E -o functrace

error_log_file=`basename "$0"`.log
echo `date` > $error_log_file
error_log_file=$(realpath $error_log_file)

# Print usage of this script
help()
{
	cat << EOF
Usage: $0 -m service --nginx --mock-database...
Quickly setup CTFd instance locally (as a service or as a process in the CLI)

Mandatory arguments:
   -m, --mode        				Mode of gunicorn (service or cli)

Optional arguments:
   -h, --help        				Displays this help
   -d, --no-install-dependencies		Do not install script dependencies

   MySQL database settings:
   --database-user        			Specifies database user (default: root)
   --database-pwd        			Specifies database password (default: dbctfdpass)
   --database-ip        			Specifies database address (default: localhost)
   --database-name        			Specifies database name (default: ctfd)
   
   Alternatively, you can set whole database URL (you can change type of db there from default mysql+pymysql)
   --database-url        			Specifies database URL (default: "mysql+pymysql://root:dbctfdpass@localhost/ctfd")
   
   --mock-database        			Mock database in the container
   --secret-key       				Specifies CTFd secret key (default: empty)
   --host-ip					Specifies IP for CTFd host (default: 127.0.0.1)
   --host-port					Specifies port for CTFd host (default: 8000)
   -u, --user					Specifies user as which the CTFd will be run (default: $(whoami))
   -n, --nginx					Install nginx proxy

EOF
   
}

failure() {
	local lineno=$1
	local msg=$2
	if [ "$1" != "0" ]; then
		echo "	> [`date`] Failed at line $lineno: '$msg'" >> $error_log_file
	fi
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR

cleanup() {
	if [ "$?" = "0" ]; then
		echo "Script finished - cleaning logs"
		read -p "Press CTRL-C to interrupt cleaning or wait 5 sec to continue" -t 5
		rm $error_log_file 2>/dev/null
	fi
}
trap cleanup EXIT

function ctrl_c() {
	echo
	echo "Interrupting..."
	exit 1
}
trap ctrl_c INT

# Env variables
WORKERS=${WORKERS:-1}
WORKER_CLASS=${WORKER_CLASS:-gevent}
ACCESS_LOG=${ACCESS_LOG:--}
ERROR_LOG=${ERROR_LOG:--}
WORKER_TEMP_DIR=${WORKER_TEMP_DIR:-/dev/shm}
SECRET_KEY=${SECRET_KEY:-}
HOST_IP=${HOST_IP:-127.0.0.1}
HOST_PORT=${HOST_PORT:-8000}
DATABASE_USER=${DATABASE_URL:-root}
DATABASE_PASSWORD=${DATABASE_URL:-dbctfdpass}
DATABASE_IP=${DATABASE_IP:-localhost}
DATABASE_NAME=${DATABASE_NAME:-ctfd}
DATABASE_URL=${DATABASE_URL:-"mysql+pymysql://$DATABASE_USER:$DATABASE_PASSWORD@$DATABASE_IP/$DATABASE_NAME"}
SERVICE_USER=${SERVICE_USER:-`whoami`}
mock_database=0
dependencies=1
install_nginx=0

# Loop that sets arguments for the script
while [ -n "$1" ]; do 
	case "$1" in
		-h|--help) 
			help
			exit;;
		-d|--no-install-dependencies)
			dependencies=0
         	shift 0
			;;
		--database-user)
			DATABASE_USER=$2
			shift
			;;
		--database-pwd)
			DATABASE_PASSWORD=$2
			shift
			;;
		--database-ip)
			DATABASE_IP=$2
			shift
			;;
		--database-name)
			DATABASE_NAME=$2
			shift
			;;
		--database-url)
			DATABASE_URL=$2
			shift
			;;
		--mock-database)
			mock_database=1
			shift 0
			;;
		--secret-key)
			SECRET_KEY=$2
			shift
			;;
		--host-ip)
			HOST_IP=$2
			shift
			;;
		--host-port)
			HOST_PORT=$2
			shift
			;;
		-u|--user)
			SERVICE_USER=$2
			shift
			;;
		-n|--nginx)
			install_nginx=1
			shift 0
			;;
		-m|--mode)
			mode=$2
			shift
			;;
		*) 
			echo "Option '$1' is not recognized"
			echo
			help
			exit 1
			;;
      esac
      shift
done

if [ -z "$mode" ]; then
   echo "Script mode must be set - manual or cli"
   exit 1
fi

sudo useradd -ms /bin/bash $SERVICE_USER 2>>$error_log_file

if [ $dependencies = "1" ]; then
	echo "Installing dependencies"
	sudo apt-get update -qq 2>>$error_log_file && sudo apt-get install -y -qq gcc python3-venv python3-dev 2>>$error_log_file
fi

# Clone CTFd
git clone https://github.com/CTFd/CTFd 2>>$error_log_file || ( echo Already cloned CTFd && cd CTFd && git pull 2>>$error_log_file )
cd CTFd

# Create python3 venv
python3 -m venv .venv-ctfd 2>>$error_log_file 
source .venv-ctfd/bin/activate

# Install dependencies
if [ $dependencies = "1" ]; then
	echo "Installing dependencies - python"
	pip install wheel 2>>$error_log_file
	pip install -r requirements.txt --no-cache-dir 2>>$error_log_file

	for d in CTFd/plugins/*; do 
		if [ -f "$d/requirements.txt" ]; then 
			pip install -r $d/requirements.txt --no-cache-dir 2>>$error_log_file
		fi
	done
fi

# Make directories for uploads and logs and change ownership of them to ctfd user
sudo mkdir /var/log/CTFd /var/uploads 2>>$error_log_file
sudo chown -R $SERVICE_USER:$SERVICE_USER /var/log/CTFd /var/uploads ${PWD} 2>>$error_log_file

# Database
if [ "${mock_database}" = "1" ]; then
	echo "Mocking database"
	sudo apt install -y -qq docker.io 2>>$error_log_file
	sudo mkdir /tmp/ctfd-mariadb-data 2>>$error_log_file
	sudo docker rm -f ctfd-mariadb 2>>$error_log_file
	sudo docker run -p 127.0.0.1:3306:3306 -v /tmp/ctfd-mariadb-data:/var/lib/mysql --name ctfd-mariadb -e MYSQL -e MARIADB_USER=$DATABASE_USER -e MARIADB_PASSWORD=$DATABASE_PASSWORD MARIADB_ROOT_PASSWORD=$DATABASE_PASSWORD -e MARIADB_DATABASE=$DATABASE_NAME --rm -d mariadb 2>>$error_log_file \
		&& echo "Database container started at 127.0.0.1:3306"
	sleep 5
fi

# Check that a .ctfd_secret_key file or SECRET_KEY envvar is set
if [ ! -f .ctfd_secret_key ] && [ -z "$SECRET_KEY" ]; then
    if [ $WORKERS -gt 1 ]; then
        echo "[ ERROR ] You are configured to use more than 1 worker."
        echo "[ ERROR ] To do this, you must define the SECRET_KEY environment variable or create a .ctfd_secret_key file."
        echo "[ ERROR ] Exiting..."
        exit 1
    fi
fi

# Install nginx proxy
if [ "${install_nginx}" = "1" ]; then
	echo "Installing nginx"
	sudo apt-get install -y -qq nginx 2>>$error_log_file || ( echo "Nginx installation failed" && exit 1 )
	sudo mkdir -p /etc/nginx/ssl 2>>$error_log_file
	sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt -subj "/C=PL/ST=Mazowieckie/L=Warsaw/emailAddress=test@test.com" 2>>$error_log_file
	sudo sed -i "s/include \/etc\/nginx\/sites-enabled\/\*\;/# include \/etc\/nginx\/sites-enabled\/\*\;/" /etc/nginx/nginx.conf 2>>$error_log_file
	sudo tee /etc/nginx/conf.d/ctfd.conf > /dev/null << EOT
		upstream ctfd_app {
			# fail_timeout=0 always retry ctfd even if it failed
			server $HOST_IP:$HOST_PORT fail_timeout=0;
		}
		# server {
		# 	# if no Host match, close the connection to prevent host spoofing
		# 	listen 80 default_server;
		# 	return 444;
		# }
		# server {
		# 	listen 8443 ssl deferred;
		# 	# You must either change this line or set the hostname of the server (e.g. through docker-compose.yml) for correct serving and ssl to be accepted
		# 	server_name \$hostname;
		# 	# SSL settings: Ensure your certs have the correct host names
		# 	ssl_certificate /etc/ssl/ctfd.crt;
		# 	ssl_certificate_key /etc/ssl/ctfd.key;
		# 	ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
		# 	ssl_ciphers HIGH:!aNULL:!MD5;
		# 	# Set connections to timout in 5 seconds
		# 	keepalive_timeout 5;
		# 	location / {
		# 	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		# 	proxy_set_header X-Forwarded-Proto https;
		# 	proxy_set_header Host \$http_host;
		# 	proxy_redirect off;
		# 	proxy_buffering off;
		# 	proxy_pass http://ctfd_app;
		# 	}
		# }
		# Redirect clients from HTTP to HTTPS
		# server {
		# 	listen 80;
		# 	server_name \$hostname;
		# 	return 301 https://\$server_name\$request_uri;
		# }
		server {
			listen 443 ssl default_server;
				listen [::]:443 ssl default_server;
			server_name _;
				ssl_certificate /etc/nginx/ssl/nginx.crt;
				ssl_certificate_key /etc/nginx/ssl/nginx.key;

			return 301 http://\$host\$request_uri;
			}
		server {
			listen 80 default_server;
			keepalive_timeout 5;
			location / {
				proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
				proxy_set_header X-Forwarded-Proto https;
				proxy_set_header Host \$http_host;
				proxy_redirect off;
				proxy_buffering off;
				proxy_pass http://ctfd_app;
			}
		}	
EOT

	sudo nginx -t 2>>$error_log_file && sudo service nginx restart 2>>$error_log_file && echo "Nginx installed" 
	if [ $? != "0" ]; then
		echo "Nginx installation failed"
		exit 1
	fi
fi

# If first argument is set to "service" - install ctfd as a systemd service
curr_path=$(pwd)
if [ "$mode" = "service" ]; then
	echo "Installing CTFd as a service"
	sudo mkdir /etc/sysconfig 2>>$error_log_file
	sudo tee /etc/sysconfig/gunicorn > /dev/null << EOT
		PATH=${curr_path}/.venv-ctfd/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
		DATABASE_URL=${DATABASE_URL}
		REVERSE_PROXY=True
EOT
	sudo tee /etc/systemd/system/gunicorn.service > /dev/null << EOT
	[Unit]
	Description=CTFd
	After=network.target

	[Service]
	Type=notify
	# the specific user that our service will run as
	PIDFile=/run/ctfd/ctfd.pid
	User=$SERVICE_USER
	Group=$SERVICE_USER
	# another option for an even more restricted service is
	# DynamicUser=yes
	# see http://0pointer.net/blog/dynamic-users-with-systemd.html
	RuntimeDirectory=gunicorn
	WorkingDirectory=${curr_path}
	EnvironmentFile=/etc/sysconfig/gunicorn
	ExecStartPre = ${curr_path}/.venv-ctfd/bin/python ping.py
	ExecStartPre = ${curr_path}/.venv-ctfd/bin/python manage.py db upgrade
	ExecStart=${curr_path}/.venv-ctfd/bin/gunicorn 'CTFd:create_app()' \
		--bind '$HOST_IP:$HOST_PORT' \
		--workers $WORKERS \
			--worker-tmp-dir "$WORKER_TEMP_DIR" \
			--worker-class "$WORKER_CLASS" \
			--access-logfile "$ACCESS_LOG" \
			--error-logfile "$ERROR_LOG"
	ExecReload=/bin/kill -s HUP \$MAINPID
	ExecStop = /bin/kill -s TERM \$MAINPID
	ExecStopPost = /bin/rm -rf /run/ctfd
	TimeoutStopSec=5
	PrivateTmp=true

	[Install]
	WantedBy=multi-user.target
EOT
	sudo systemctl start gunicorn 2>>$error_log_file && echo "CTFd installed as a service"
	if [ $? != "0" ]; then
		echo "CTFd installation as a service failed"
		exit 1
	fi

# If first argument is anything else than "service" - install it and run in current CLI
elif [ "$mode" = "cli" ]; then
	sudo -i -u $SERVICE_USER bash << EOF
	cd ${curr_path}
	pwd

	source .venv-ctfd/bin/activate

	export DATABASE_URL=${DATABASE_URL}

	# Ensures that the database is available
	python ping.py

	# Initialize database
	python manage.py db upgrade

	# Start CTFd
	echo "Starting CTFd"
	exec gunicorn 'CTFd:create_app()' \
    	--bind '$HOST_IP:$HOST_PORT' \
    	--workers $WORKERS \
    	--worker-tmp-dir "$WORKER_TEMP_DIR" \
    	--worker-class "$WORKER_CLASS" \
    	--access-logfile "$ACCESS_LOG" \
    	--error-logfile "$ERROR_LOG"
EOF
else
	echo "Wrong argument passed (manual or service accepted)"
	exit 1
fi
