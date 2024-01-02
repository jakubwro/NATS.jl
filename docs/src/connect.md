
# Connection

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
| `tls_ca_cert_path`     | `NATS_CA_CERT_PATH`      |             | no
| `tls_client_cert_path` | `NATS_CLIENT_CERT_PATH`  |             | no
| `tls_client_key_path`  | `NATS_CLIENT_KEY_PATH`   |             | no

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
