# NATS.jl - NATS client for Julia.

NATS.jl allows to connect to [NATS](https://nats.io) cluster from Julia and use
patterns like [publish-subscribe](https://docs.nats.io/nats-concepts/core-nats/pubsub),
[request-reply](https://docs.nats.io/nats-concepts/core-nats/reqreply), and 
[queue groups](https://docs.nats.io/nats-concepts/core-nats/queue).

> **Warning**
> 
> NATS is not a reliable communication protocol by design. Just like raw TCP connection it provides just at most once message delivery guarantees.
> For reliable communication you need to implement message acknowledgements in client applications or use JetStream protocol build on top of NATS.

## Architecture overview

Each connection creates several asynchronous tasks for monitoring connection state, receiving messages from server, publishing messages to server. Flow is like this:
1. Connect method is called
2. Task for monitoring connection state is created
3. Above task spawns two more tasks for inbound and outbound communication
4. If any of tasks fails monitoring task tries to reconnect by spawning them again

Those tasks should be scheduled on interactive threads to ensure fast responses to server, for instance, in case of [PING](https://jakubwro.github.io/NATS.jl/dev/protocol/#NATS.Ping) message. To not block them tasks handling actual processing of subscription messages are ran in `:default` threadpool. Implication of this to ensure everything works smoothly user should do one of things:
 - start `julia` with at least one interactive thread, see `--threads` option
 - ensure all handler methods are not CPU intensive if ran with single thread

## Interrupt handling

Graceful handling of interrupt is important in scenario of deployment to `kubernetes` cluster to handle pods auto scaling.
There are several issues with Julia if it comes to handling signals:
1. by default when SIGINT is delivered process is exited immediately, this can be prevented by calling `Base.exit_on_sigint` with `false` parameter.
2. even when this is configured interrupts are delivered to all tasks running on thread 1. Depending on `--threads` configuration this thread might run all tasks (when `--threads 1` which is default) or it can handle tasks scheduled on interactive threadpool (with `--threads M,N` where N is number of interactive threads). 

To workaround this behavior all tasks started by `NATS.jl` are started inside `disable_sigint` wrapper, exception to this is special task designated to handling interrupts and scheduled on thread 1 with `sticky` flag set to `true`, what is achieved with `@async` macro.
Limitation to this approach is that tasks started by user of `NATS.jl` or other packages may start tasks that will intercept `InterruptException` may ignore it or introduce unexpected behavior. On user side this might be mitigated by wrapping tasks functions into `disable_sigint`, also entrypoint to application should do this or handle interrupt correctly, for instance by calling `NATS.drain` to close all connections and wait until it is done.

Future improvements in this matter might be introduced by [open PR](https://github.com/JuliaLang/julia/pull/49541)

Current `NATS.jl` approach to handling signals is based on code and discussions from this PR. 

## List of all environment variables

| `ENV` variable                                | Used in      | Default if not set | Description
|-----------------------------------------------|--------------|--------------------|-------------
| `NATS_AUTH_TOKEN`                             | `connect`    | `nothing`          | Client authorization token   
| `NATS_CONNECT_URL`                            | `connect`    | `localhost:4222`   | Connection url, multiple urls to the same NATS cluster can be provided, for example `nats:://localhost:4222,tls://localhost:4223`    
| `NATS_DRAIN_POLL_INTERVAL_SECONDS`            | `connect`    | `0.2`              | Interval in seconds how often `drain` will check if all buffers are consumed.
| `NATS_DRAIN_TIMEOUT_SECONDS`                  | `connect`    | `5.0`              | Maximum time (in seconds) `drain` will block before returning error
| `NATS_ENQUEUE_WHEN_DISCONNECTED`              | `connect`    | `true`             | Allows buffering outgoing messages during disconnection
| `NATS_IGNORE_ADVERTISED_SERVERS`              | `connect`    | `false`            | Ignores other cluster servers returned by server
| `NATS_JWT`                                    | `connect`    | `nothing`          | The JWT that identifies a user permissions and account                                  
| `NATS_MAX_PINGS_OUT`                          | `connect`    | `3`                | How many pings in a row might fail before connection will be restarted
| `NATS_NKEY`                                   | `connect`    | `nothing`          | The public NKey to authenticate the client
| `NATS_NKEY_SEED`                              | `connect`    | `nothing`          | the private NKey to authenticate the client
| `NATS_PASS`                                   | `connect`    | `nothing`          | Connection password, can be also passed in url `nats://john:passw0rd@localhost:4223` but env variable has higher priority
| `NATS_PEDANTIC`                               | `connect`    | `false`            | Turns on additional strict format checking, e.g. for properly formed subjects
| `NATS_PING_INTERVAL`                          | `connect`    | `120.0`            | Interval in seconds how often server should be pinged to check connection health
| `NATS_RECONNECT_FACTOR`                       | `connect`    | `5.0`                 | Exponential reconnect delays configuration
| `NATS_RECONNECT_FIRST_DELAY`                  | `connect`    | `0.1`                 | Exponential reconnect delays configuration
| `NATS_RECONNECT_JITTER`                       | `connect`    | `0.1`                 | Exponential reconnect delays configuration
| `NATS_RECONNECT_MAX_DELAY`                    | `connect`    | `5.0`                 | Exponential reconnect delays configuration
| `NATS_RECONNECT_RETRIES`                      | `connect`    | `220752000000000000`  | Exponential reconnect delays configuration
| `NATS_REQUEST_TIMEOUT_SECONDS`                | `request`    | `5.0`              | Time how long `request` will block before returning error
| `NATS_RETAIN_SERVERS_ORDER`                   | `connect`    | `false`            | Changes connection url selection policy from random to sequence they were provided.
| `NATS_RETRY_ON_INIT_FAIL`                     | `connect`    | `false`            | If set to true `connect` will not throw and error if connection init fails, but will continue retrying in background returning immediately connection in `CONNECTING` state.
| `NATS_SEND_BUFFER_LIMIT_BYTES`                | `connect`    | `2097152`          | Soft limit for buffer of messages pending. If too small operations that send messages to server (e.g. `publish`) may throw an exception
| `NATS_SUBSCRIPTION_CHANNEL_SIZE`              | `subscribe`  | `524288`           | How many messages waiting for processing subscription buffer can hold, if it gets full messages will be dropped.
| `NATS_SUBSCRIPTION_ERROR_THROTTLING_SECONDS`  | `subscribe`  | `5.0`              | How often subscription handler exceptions are reported in logs
| `NATS_TLS_CA_PATH`                            | `connect`    | `nothing`          | Path to CA certificate file if TLS is used
| `NATS_TLS_CERT_PATH`                          | `connect`    | `nothing`          | Path to client certificate file if TLS is used
| `NATS_TLS_KEY_PATH`                           | `connect`    | `nothing`          | Path to client private certificate file if TLS is used 
| `NATS_TLS_REQUIRED`                           | `connect`    | `false`            | Forces TLS connection. TLS can be also forced by using url with `tls` scheme, example `tls://localhost:4223`
| `NATS_USER`                                   | `connect`    | `nothing`          | Connection username, can be also passed in url `nats://john:passw0rd@localhost:4223` but env variable has higher priority
| `NATS_VERBOSE`                                | `connect`    | `false`            | Turns on protocol acknowledgements
