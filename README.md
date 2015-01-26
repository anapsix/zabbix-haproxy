HAProxy Zabbix Discovery and Template
=====================================

[Zabbix](http://zabbix.com) is a powerful open-source monitoring platform, capable of monitoring anything and everything, with the right configuration.
Zabbix's powerful Discovery capability is awesome, making it possible to automatically register hosts as they come online or monitor database servers without having to add individual databases and tables one by one.
This repo contains everything you need to discover and monitor HAProxy frontends, backends and backend servers.

[HAProxy](http://www.haproxy.org/) is an awesome multi-purpose load-balancer.

> HAProxy is a free, very fast and reliable solution offering high availability, load balancing, and proxying for TCP and HTTP-based applications.
> It is particularly suited for very high traffic web sites and powers quite a number of the world's most visited ones. Over the years it has become the de-facto standard opensource load balancer, is now shipped with most mainstream Linux distributions, and is often deployed by default in cloud platforms.


### Prerequisites

* Zabbix Server >= 2.x
* Zabbix Frontend >= 2.x
* HAProxy >= 1.3
* Socat

### Instructions

1. Place `userparameter_haproxy.conf` into `/etc/zabbix/zabbix_agentd.d/` directory, assuming you have Include set in `zabbix_agend.conf`, like so:

    ### Option: Include
    # You may include individual files or all files in a directory in the configuration file.
    # Installing Zabbix will create include directory in /usr/local/etc, unless modified during the compile time.
    #
    # Mandatory: no
    # Default:
    Include=/etc/zabbix/zabbix_agentd.d/

2. Place `haproxy_discovery.sh` into `/usr/local/bin/` directory and make sure it's executable (`sudo chmod +x /usr/local/bin/haproxy_discovery.sh`)
3. Import `haproxy_zbx_template.xml` template via Zabbix Web UI interface (provided by `zabbix-frontend-php` package)
4. Configure HAProxy control socket
  - [Configure HAProxy](http://cbonte.github.io/haproxy-dconv/configuration-1.5.html#9.2) to listen on `/run/haproxy/info.sock`
  - or set custom socket path in checks (set `{$HAPROXY_SOCK}` macro to your custom socket path)
  - or update `userparameter_haproxy.conf` and `haproxy_discovery.sh` with your socket path

    # haproxy.conf snippet
    # haproxy read-only non-admin socket
    ## (user level permissions are required, admin level will work as well, though not necessary)
    global
      stats socket /run/haproxy/info.sock  mode 666 level user

5. Verify on server with HAProxy installed:

    anapsix@lb1:~$ sudo zabbix_agentd -t haproxy.list.discovery[FRONTEND]
      haproxy.list.discovery[FRONTEND]              [t|{"data":[{"{#FRONTEND_NAME}":"http-frontend"},{"{#FRONTEND_NAME}":"https-frontend"}]}]
    
    anapsix@lb1:~$ sudo zabbix_agentd -t haproxy.list.discovery[BACKEND]
      haproxy.list.discovery[BACKEND]               [t|{"data":[{"{#BACKEND_NAME}":"www-backend"},{"{#BACKEND_NAME}":"api-backend"}]}]
    
    anapsix@lb1:~$ sudo zabbix_agentd -t haproxy.list.discovery[SERVERS]
      haproxy.list.discovery[SERVERS]               [t|{"data":[{"{#BACKEND_NAME}":"www-backend","{#SERVER_NAME}":"www01"},{"{#BACKEND_NAME}":"www-backend","{#SERVER_NAME}":"www02"},{"{#BACKEND_NAME}":"www-backend","{#SERVER_NAME}":"www03"},{"{#BACKEND_NAME}":"api-backend","{#SERVER_NAME}":"api01"},{"{#BACKEND_NAME}":"api-backend","{#SERVER_NAME}":"api02"},{"{#BACKEND_NAME}":"api-backend","{#SERVER_NAME}":"api03"}]}]

6. Add hosts with HAProxy installed to just imported Zabbix HAProxy template.
7. Wait for discovery.. Frontend(s), Backend(s) and Server(s) should show up under Host Items.  
   An easy way to see all data is via _Overview_ (make sure to pick right Group, one of the "HAProxy" applications and select _Data_ as Type)


### Contributors

Anastas Dancha <anapsix@random.io>

### License

[MIT](http://opensource.org/licenses/MIT)

    The MIT License (MIT)
    
    Copyright (c) 2015 "Anastas Dancha <anapsix@random.io>"
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
