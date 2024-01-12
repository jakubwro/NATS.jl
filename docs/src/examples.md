# Quick start

Start nats-server:

```
docker run -p 4222:4222 nats:latest
```

## Check ping - pong working

```@repl
using NATS
nc = NATS.connect()
@time NATS.ping(nc) # First one may be slow due to compilation
@time NATS.ping(nc)
```

## Publish subscribe

```@repl
using NATS
nc = NATS.connect()
sub = subscribe(nc, "test_subject") do msg
          @show payload(msg)
      end
publish(nc, "test_subject", "Hello.")
sleep(0.2) # Wait for message.
drain(nc, sub)
publish(nc, "test_subject", "Hello.") # Ater drain msg won't be delivared.
```

## Request reply

```bash
> nats reply help.please 'OK, I CAN HELP!!!'

20:35:19 Listening on "help.please" in group "NATS-RPLY-22"
```

```@repl
using NATS
nc = NATS.connect()
rep = @time NATS.request(nc, "help.please");
payload(rep)
```

## Work queues

If `subscription` or `reply` is configured with `queue_group`, messages will be distributed equally between subscriptions with the same group.

```@repl
using NATS
connection = NATS.connect()
sub1 = reply(connection, "some_subject"; queue_group="group1") do
           "Reply from worker 1"
       end
sub2 = reply(connection, "some_subject"; queue_group="group1") do
           "Reply from worker 2"
       end
request(String, connection, "some_subject")
request(String, connection, "some_subject")
request(String, connection, "some_subject")
request(String, connection, "some_subject")
request(String, connection, "some_subject")
request(String, connection, "some_subject")
request(String, connection, "some_subject")
drain(connection, sub1)
drain(connection, sub2)
```
