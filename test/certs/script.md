```
openssl req -new -newkey rsa:4096 -x509 -sha256 -days 365 -nodes -out nats.crt -keyout nats.key -addext "subjectAltName = DNS:localhost, DNS:nats"
```

```
openssl req -new -newkey rsa:4096 -x509 -sha256 -days 365 -CA nats.crt -CAkey nats.key -nodes -out client.crt -keyout client.key  -addext "subjectAltName = DNS:localhost, email:jakub@localhost"
```

```
docker create -v $(pwd)/test/certs:/certs -v $(pwd)/test/configs/nats-server-tls-auth.conf:/nats-server.conf  -p 4225:4222 nats
```

```
docker create -p 4223:4222 -v $(pwd)/test/certs:/certs -it nats --tls --tlscert /certs/nats.crt --tlskey /certs/nats.key
```

```
nats reply help.please 'OK, I CAN HELP!!!' --server localhost:4223 --tlsca test/certs/nats.crt
```

```
docker create -v $(pwd)/test/configs/nats-server-nkey-auth.conf:/nats-server.conf -p 4224:4222 nats
```