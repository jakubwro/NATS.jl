# JetChannel

## Example

```@repl
using NATS
using NATS.JetStream
nc = NATS.connect()
ch = JetChannel{String}(nc, "example_jetstream_channel");
put!(ch, "test");
take!(ch)
t = @async take!(ch)
sleep(1)
istaskdone(t)
put!(ch, "some value");
sleep(0.1)
t.result
destroy!(ch)
```