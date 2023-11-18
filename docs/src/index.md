# NATS.jl - NATS client for Julia.

NATS.jl allows to connect to [NATS](https://nats.io) cluster from Julia.
It allows to implement patterns like [publish-subscribe](https://docs.nats.io/nats-concepts/core-nats/pubsub), [request-reply](https://docs.nats.io/nats-concepts/core-nats/reqreply), and [queue groups](https://docs.nats.io/nats-concepts/core-nats/queue).

> **Warning**
> NATS is not a reliable communication protocol by design. Just like raw TCP connection it provides just at most once message delivery guarantees.
> For reliable communication you need to implement message acknowledgements in client applications or use JetStream protocol build on top of NATS. See [JetStream.jl](https://github.com/jakubwro/JetStream.jl) project.

## Architecture overview

Each connection creates several asynchronous tasks for monitoring connection state, receiving messages from server, publishing messages to server. Flow is like this:
1. Connect method is called
2. Task for monitoring connection state is created
3. Above task spawns two more tasks for inbound and outbound communication
4. If any of tasks fails monitoring task tries to reconnect by spawning them again

Those tasks should be scheduled on interactive threads to ensure fast responses to server, for instance, in case of [PING](/protocol/#NATS.Ping) message. To not block them tasks handling actual processing of subscription messages are ran in `:default` threadpool. Implication of this to ensure everything works smoothly user should do one of things:
 - start `julia` with at least one interactive thread, see `--threads` option
 - ensure all handler methods are not CPU intensive if ran with single thread

## Interrupt handling

Gracefull handling of interrupt is important in scenario of deployment in `kubernetes` cluster to handle pods autoscalling.
There are several issues with Julia if it comes to handling signals:
1. by default when SIGINT is delivered process is exited immediately, this can be prevented by calling `Base.exit_on_sigint` with `false` parameter.
2. even when this is configured interrupts are delivered to all tasks running on thread 1. Depending on `--threads` configuration this thread might run all tasks (when `--threads 1` which is default) or it can handle tasks scheduled on interactive threadpool (with `--threads M,N` where N is number of interactive threads). 

To workaround this behavior all tasks started by `NATS.jl` are started inside `disable_sigint` wrapper, exception to this is special task designated to handling interrupts and scheduled on thread 1 with `sticky` flag set to `true`, what is achieved with `@async` macro.
Limitation to this approach is that tasks started by user of `NATS.jl` or other packages may start tasks that will intercept `InterruptException` may ignore it or introduce unexpected behavior. On user side this might be mitigated by wrapping tasks functions into `disable_sigint`, also entrypoint to application should do this or handle interrupt correctly, for instance by calling `NATS.drain` to close all connections and wait until it is done.

Future improvements in this matter might be introduced by [](https://github.com/JuliaLang/julia/pull/49541)

Current `NATS.jl` approach to handling signals is based on code and discussions from this PR. 
