[![Build Status](https://travis-ci.org/clear-code/github-web-hooks-receiver.svg?branch=master)](https://travis-ci.org/clear-code/github-web-hooks-receiver)

# GitHub Web hooks receiver

This is a Rack based web application that can process POST request from GitHub, GitLab and GHE.

## Set up

Prepare following files.

/home/github-web-hooks-receiver/github-web-hooks-receiver/Gemfile:
```
source "https://rubygems.org"
gem "github-web-hooks-receiver"
# gem "unicorn"   # Enable this line if you use Unicorn.
# gem "passenger" # Enable this line if you use latest Passenger.
```

/home/github-web-hooks-receiver/github-web-hooks-receiver/config.ru:
```ruby
require "yaml"
require "pathname"
require "github-web-hooks-receiver"

use Rack::CommonLogger
use Rack::Runtime
use Rack::ContentLength

base_dir = Pathname(__FILE__).dirname
config_file = base_dir + "config.yaml"

options = YAML.load_file(config_file.to_s)

map "/post-receiver/" do
  run GitHubWebHooksReceiver::App.new(options)
end
```

/home/github-web-hooks-receiver/github-web-hooks-receiver/config.yaml:
```
mirrors_directory: /path/to/mirrors
git_commit_mailer: /path/to/git-commit-mailer
to: receiver@example.com
sender: sender@example.com
add_html: true
owners:
  groonga:
    to: groonga-commit@lists.sourceforge.jp
```

### Apache + Passenger

On Debian GNU/Linux wheezy.

See also [Phusion Passenger users guide, Apache version](https://www.phusionpassenger.com/documentation/Users%20guide%20Apache.html).

Install Passenger or write `gem "passenger"` in your Gemfile.

```
$ sudo apt-get install -y ruby-passenger
```

Install gems.

```
$ sudo -u github-web-hooks-receiver -H bundle install --path vendor/bundle
```

Prepare following files.

/etc/apache2/mods-available.conf:
```
PassengerRoot /path/to/passenger-x.x.x
PassengerRuby /path/to/ruby

PassengerMaxRequests 100
```

/etc/apache2/mods-available.load:
```
LoadModule passenger_module /path/to/mod_passenger.so
```

/etc/apache2/sites-available/github-web-hooks-receiver:
```
<VirtualHost *:80>
  ServerName github-web-hooks-receiver.example.com
  DocumentRoot /home/github-web-hooks-receiver/github-web-hooks-receiver/public
  <Directory /home/github-web-hooks-receiver/github-web-hooks-receiver/public>
     AllowOverride all
     Options -MultiViews
  </Directory>

  ErrorLog ${APACHE_LOG_DIR}/github-web-hooks-receiver_error.log
  CustomLog ${APACHE_LOG_DIR}/github-web-hooks-receiver_access.log combined

  AllowEncodedSlashes On
  AcceptPathInfo On
</VirtualHost>
```

Enable the module.

```
$ sudo a2enmod passenger
```

Enable the virtual host.

```
$ sudo a2ensite github-web-hooks-receiver
```

Restart web server.

```
$ sudo service apache2 restart
```

### Nginx + Unicorn

Prepare following files.

/etc/nginx/sites-enabled/github-web-hooks-receiver:
```
upstream github-web-hooks-receiver {
    server unix:/tmp/unicorn-github-web-hooks-receiver.sock;
}

server {
    listen 80;
    server_name github-web-hooks-receiver.example.com;
    access_log /var/log/nginx/github-web-hooks-receiver.example.com-access.log combined;

    root /srv/www/github-web-hooks-receiver;
    index index.html;

    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    #proxy_redirect off;

    location / {
        root /home/github-web-hooks-receiver/github-web-hooks-receiver/public;
        include maintenance;
        if (-f $request_filename){
            break;
        }
        if (!-f $request_filename){
            proxy_pass http://github-web-hooks-receiver;
            break;
        }
    }
}
```

/home/github-web-hooks-receiver/github-web-hooks-receiver/unicorn.conf:
```
# -*- ruby -*-
worker_processes 2
working_directory "/home/github-web-hooks-receiver/github-web-hooks-receiver"
listen '/tmp/unicorn-github-post-receiver.sock', :backlog => 1
timeout 120
pid 'tmp/pids/unicorn.pid'
preload_app true
stderr_path 'log/unicorn.log'
stdout_path "log/stdout.log"
user "github-web-hooks-receiver", "github-web-hooks-receiver"
```

/home/github-web-hooks-receiver/bin/github-web-hooks-receiver:
```
#! /bin/zsh
BASE_DIR=/home/github-web-hooks-receiver/github-web-hooks-receiver
export RACK_ENV=production
cd  $BASE_DIR
rbenv version

command=$1

function start() {
  mkdir -p $BASE_DIR/tmp/pids
  mkdir -p $BASE_DIR/log
  bundle exec unicorn -D -c unicorn.conf config.ru
}

function stop() {
  kill $(cat $BASE_DIR/tmp/pids/unicorn.pid)
}

function restart() {
  kill -USR2 $(cat $BASE_DIR/tmp/pids/unicorn.pid)
}

$command
```

Install gems.

```
$ sudo -u github-web-hooks-receiver -H bundle install --path vendor/bundle
```

Run the application.

```
$ sudo -u github-web-hooks-receiver -H ~github-web-hooks-receiver/bin/github-web-hooks-receiver start
```

## Configuration

You need to edit config.yaml to configure this web application.
See config.yaml.example and test codes.
