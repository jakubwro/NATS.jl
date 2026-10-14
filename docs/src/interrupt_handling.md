# Handling SIGINT

When SIGINT is delivered, for instance when pressing `CTRL+C` in an interactive session or externally by a container runtime (for instance a Kubernetes pod autoscaler) it is hard to ensure the proper action is executed.

Julia tasks might be scheduled on two threadpools, `:interactive` and `:default` and the sizes of those threadpools are configured by the `--threads` option. The first one is intended to run short interactive tasks (like network communication), the second one is for more CPU intensive operations that might block a thread for a longer time.

When `SIGINT` is delivered it is delivered only to the first thread and which threadpool it handles depends on the `--threads` configuration.

For instance:
 - `--threads 1` runs 0 `:interactive` threads and 1 `:default` threads.
 - `--threads 1,1` runs 1 `:interactive` threads and 1 `:default` threads.
 - `--threads 2,3` runs 3 `:interactive` threads and 2 `:default` threads.

To ensure the `drain` in `NATS` action is executed on an interrupt signal `julia` should be run with exactly one `:interactive` thread. Otherwise some CPU intensive tasks may be scheduled on the first thread, or in case when there are more than one interactive threads, the handler might be scheduled on a different thread and miss the interrupt signal.

To ensure the signal is delivered to the tasks that knows how to handle it, all `:interactive` tasks are wrapped into the `disable_sigint` method except the one that have proper logic for connection draining.
