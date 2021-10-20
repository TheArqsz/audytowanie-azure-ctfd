#!/usr/bin/env bash
# Quickly setup CTFd instance locally (as a service or as a process in the CLI)
#
# Copyright 2021 TheArqsz

sudo apt-get update -q && sudo apt-get install -y -qq gcc python3-dev nginx

# Clone CTFd
git clone https://github.com/CTFd/CTFd 2>/dev/null || ( echo Already cloned CTFd && cd CTFd && git pull 2>/dev/null )
cd CTFd

# Create python3 venv
python3 -m venv .venv-ctfd
source .venv-ctfd/bin/activate

# Install dependencies
pip install wheel
pip install -r requirements.txt --no-cache-dir

for d in CTFd/plugins/*; do 
        if [ -f "$d/requirements.txt" ]; then 
		pip install -r $d/requirements.txt --no-cache-dir; 
	fi; 
done;

# Make directories for uploads and logs and change ownership of them to ctfd user
sudo mkdir /var/log/CTFd /var/uploads
sudo chown -R ctfd:ctfd /var/log/CTFd /var/uploads ${PWD}

set -euo pipefail

# Env variables
WORKERS=${WORKERS:-1}
WORKER_CLASS=${WORKER_CLASS:-gevent}
ACCESS_LOG=${ACCESS_LOG:--}
ERROR_LOG=${ERROR_LOG:--}
WORKER_TEMP_DIR=${WORKER_TEMP_DIR:-/dev/shm}
SECRET_KEY=${SECRET_KEY:-}
HOST_IP=${HOST_IP:-127.0.0.1}
HOST_PORT=${HOST_PORT:-8000}

# Check that a .ctfd_secret_key file or SECRET_KEY envvar is set
if [ ! -f .ctfd_secret_key ] && [ -z "$SECRET_KEY" ]; then
    if [ $WORKERS -gt 1 ]; then
        echo "[ ERROR ] You are configured to use more than 1 worker."
        echo "[ ERROR ] To do this, you must define the SECRET_KEY environment variable or create a .ctfd_secret_key file."
        echo "[ ERROR ] Exiting..."
        exit 1
    fi
fi

# If first argument is set to "service" - install ctfd as a systemd service
if [ "${1-manual}" = "service" ]; then
	sudo tee /etc/systemd/system/gunicorn.service> /dev/null << EOT
	[Unit]
	Description=CTFd
	After=network.target

	[Service]
	Type=notify
	# the specific user that our service will run as
	PIDFile=/run/ctfd/ctfd.pid
	User=ctfd
	Group=ctfd
	# another option for an even more restricted service is
	# DynamicUser=yes
	# see http://0pointer.net/blog/dynamic-users-with-systemd.html
	RuntimeDirectory=gunicorn
	WorkingDirectory=/home/ctfdadmin/CTFd
	Environment="PATH=/home/ctfdadmin/CTFd/.venv-ctfd/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
	ExecStartPre = /home/ctfdadmin/CTFd/.venv-ctfd/bin/python ping.py
	ExecStartPre = /home/ctfdadmin/CTFd/.venv-ctfd/bin/python manage.py db upgrade
	ExecStart=/home/ctfdadmin/CTFd/.venv-ctfd/bin/gunicorn 'CTFd:create_app()' \
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
	sudo systemctl start gunicorn

# If first argument is anything else than "service" - install it and run in current CLI
else
	curr_path=$(pwd)
	sudo -i -u ctfd bash << EOF
	cd ${curr_path}
	pwd

	source .venv-ctfd/bin/activate

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
fi

# Install nginx proxy
sudo sed -i "s/include \/etc\/nginx\/sites-enabled\/\*\;/# include \/etc\/nginx\/sites-enabled\/\*\;/" /etc/nginx/nginx.conf
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
	# 	server_name $hostname;
	# 	# SSL settings: Ensure your certs have the correct host names
	# 	ssl_certificate /etc/ssl/ctfd.crt;
	# 	ssl_certificate_key /etc/ssl/ctfd.key;
	# 	ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
	# 	ssl_ciphers HIGH:!aNULL:!MD5;
	# 	# Set connections to timout in 5 seconds
	# 	keepalive_timeout 5;
	# 	location / {
	# 	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	# 	proxy_set_header X-Forwarded-Proto https;
	# 	proxy_set_header Host $http_host;
	# 	proxy_redirect off;
	# 	proxy_buffering off;
	# 	proxy_pass http://ctfd_app;
	# 	}
	# }
	# Redirect clients from HTTP to HTTPS
	# server {
	# 	listen 80;
	# 	server_name $hostname;
	# 	return 301 https://$server_name$request_uri;
	# }
	server {
		listen 80 default_server;
		keepalive_timeout 5;
		location / {
			proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
			proxy_set_header X-Forwarded-Proto https;
			proxy_set_header Host $http_host;
			proxy_redirect off;
			proxy_buffering off;
			proxy_pass http://ctfd_app;
		}
	}	
EOT

sudo nginx -t && sudo service nginx restart