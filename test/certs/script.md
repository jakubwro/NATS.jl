```
openssl req -new -newkey rsa:4096 -x509 -sha256 -days 365 -nodes -out nats.crt -keyout nats.key -addext "subjectAltName = DNS:localhost, DNS:nats"
```

```
docker create -p 4223:4222 -v $(pwd)/test/certs:/certs -it nats --tls --tlscert /certs/nats.crt --tlskey /certs/nats.key
```

```
nats reply help.please 'OK, I CAN HELP!!!' --server localhost:4223 --tlsca test/certs/nats.crt
```