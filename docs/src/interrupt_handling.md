# Handling SIGINT

When SIGINT is delivered, for instance when pressing `CTRL+C` in interactive session or externally by container runtime (for instance Kubernetes pod autoscaller) it is hard to ensure proper action is executed.

Julia tasks might be scheduled on two threadpools, `:interactive` and `:default` and sizes of those threadpools are configured by `--threads` option. First one is intended to run short interactive tasks (like network communication), second one is for more CPU intensive operations that might block a thread for longer time.

When `SIGINT` is delivered it is delivered only to the first thread and which threadpool it handles depends on `--threads` configuration.

For instance:
 - `--threads 1` runs 0 `:interactive` threads and 1 `:default` threads.
 - `--threads 1,1` runs 1 `:interactive` threads and 1 `:default` threads.
 - `--threads 2,3` runs 3 `:interactive` threads and 2 `:default` threads.

To ensure `drain` in `NATS` action is executed on interrupt signal `julia` should be run with exactly one `:interactive` thread. Otherwise some cpu intensive tasks may be scheduled on the first thread, or in case when there are more than one interactive threads, handler might be scheduled on different thread and miss interrupt signal.

To ensure signal is delivered to the tasks that knows how to handle it, all `:interactive` tasks are wrapped into `disable_sigint` method except the one that have proper logic for connection draining.
