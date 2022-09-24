# How to run the Docker-Setup

```
git clone <repo> && cd <repo>

docker build -t regolancer --force-rm .

```

edit config file in `./regolancer_data/config.json`:

if you run the setup on your host, you need to grep the local ip of the eth0 interface

Use the command `ip addr`, and check for the ip (usally it starts with 192...)

Input this ip in the connect section of the config
```
 "connect":"192.168.176.3:10009",
```

create an alias for the docker-container

`alias regolancer='docker run --name regolancer --rm -v ${PWD}/regolancer_data:/app/.regolancer  regolancer --config=.regolancer/config.json'`

now you can use it with:


`regolancer -h`

or

`regolancer --to=chanid`