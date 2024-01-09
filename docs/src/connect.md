
# Connection

## Connection lifecycle

```@eval
using GraphViz

lifecycle = dot""" digraph G {
    CONNECTING -> CONNECTED -> DRAINING -> DRAINED
    CONNECTED -> CONNECTING [label="TCP failure", fontname="Courier New", fontsize=5, color="#aa0000", fontcolor="#aa0000"]
    CONNECTING -> DISCONNECTED [label="reconnect\nretries\nexhausted", fontname="Courier New", fontsize=5, color="#aa0000", fontcolor="#aa0000"]
    DISCONNECTED -> CONNECTING [label="reconnect()", fontname="Courier New", fontsize=5]
    DISCONNECTED -> DRAINING [lable="unsubscribe and\nprocess messages"]
}"""

GraphViz.layout!(lifecycle, engine="dot")
open("lifecycle.svg", write = true) do f
    GraphViz.render(f, lifecycle)
end
nothing
```
![](lifecycle.svg)


## Connecting to NATS cluster

To use NATS it is needed to crate connection handle with `connect` function. Connection creates asynchronous tasks to handle messages from server, sending published messages, monitor state of TCP connection and reconnect on network failure.

There are several `ENV` variables defined to provide default parameters for `connect`. It is advised to rather define `ENV` variables and use parameter less invocation like `NATS.connect()` for better code portability.

| Parameter          | `ENV` variable          |  Default value   | Sent to server |
|--------------------|-------------------------|------------------|-----------------|
| `url`              | `NATS_CONNECT_URL`      | `localhost:4222` | no
| `send_buffer_size` | `NATS_SEND_BUFFER_SIZE` | `2097152`        | no
| `verbose`          | `NATS_VERBOSE`          | `false`          | yes
| `verbose`          | `NATS_VERBOSE`          | `false`          | yes
| `pedantic`         | `NATS_PEDANTIC`         | `false`          | yes
| `tls_required`     | `NATS_TLS_REQUIRED`     | `false`          | yes
| `auth_token`       | `NATS_AUTH_TOKEN`       |                  | yes
| `user`             | `NATS_USER`             |                  | yes
| `pass`             | `NATS_PASS`             |                  | yes
| `jwt`              | `NATS_JWT`              |                  | yes
| `nkey`             | `NATS_NKEY`             |                  | yes
| `nkey_seed`        | `NATS_NKEY_SEED`        |                  | no
| `tls_ca_path`      | `NATS_TLS_CA_PATH`      |                  | no
| `tls_cert_path`    | `NATS_TLS_CERT_PATH`    |                  | no
| `tls_key_path`     | `NATS_TLS_KEY_PATH`     |                  | no

| Parameter                   | `ENV` variable                   |  Default value   | Sent to server |
|-----------------------------|----------------------------------|------------------|-----------------|
| `ping_interval`             | `NATS_PING_INTERVAL_SECONDS`     | `120`            | no
| `max_pings_out`             | `NATS_MAX_PINGS_OUT`             | `2`              | no
| `retry_on_init_fail`        | `NATS_RETRY_ON_INIT_FAIL`        | `false`          | no
| `ignore_advertised_servers` | `NATS_IGNORE_ADVERTISED_SERVERS` | `false`          | no
| `retain_servers_order`      | `NATS_RETAIN_SERVERS_ORDER `     | `false`          | no

Additionally reconnect `reconnect_delays` default `ExponentialBackOff` might be configured from `ENV` variables. This is recommended to configure it with them rather than pass delays as argument.

| `ENV` variable                  |  Default value       |
|---------------------------------|----------------------|
| `DEFAULT_RECONNECT_RETRIES`     | `220752000000000000` |
| `DEFAULT_RECONNECT_FIRST_DELAY` | `0.0001`             |
| `DEFAULT_RECONNECT_MAX_DELAY`   | `2.0`                |
| `DEFAULT_RECONNECT_FACTOR`      | `5.0`                |
| `DEFAULT_RECONNECT_JITTER`      | `0.1`                |

```@docs
connect
```

## Disconnecting

To close connection `drain` function is provided.

```@docs
drain
```