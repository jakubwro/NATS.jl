include("sub_sync.jl")
include("sub_async.jl")

"""
$(SIGNATURES)

Subscribe to a subject.

Optional keyword arguments are:
- `connection`: connection to be used, if not specified `default` connection is taken
- `queue_group`: NATS server will distribute messages across queue group members
- `async_handlers`: if `true` task will be spawn for each `f` invocation, otherwise messages are processed sequentially, default is `false`
- `channel_size`: maximum items buffered for processing, if full messages will be ignored, default is `$SUBSCRIPTION_CHANNEL_SIZE`
- `error_throttling_seconds`: time intervals in seconds that handler errors will be reported in logs, default is `$SUBSCRIPTION_ERROR_THROTTLING_SECONDS` seconds
"""
function subscribe(
    f,
    subject::String;
    connection::Connection = connection(:default),
    queue_group::Union{String, Nothing} = nothing,
    async_handlers = false,
    channel_size = SUBSCRIPTION_CHANNEL_SIZE,
    error_throttling_seconds = SUBSCRIPTION_ERROR_THROTTLING_SECONDS
)
    arg_t = argtype(f)
    find_msg_conversion_or_throw(arg_t)
    f_typed = _fast_call(f, arg_t)
    sid = new_sid(connection)
    sub = Sub(subject, queue_group, sid)
    sub_stats = Stats()
    channel = _start_tasks(f_typed, sub_stats, connection.stats, async_handlers, subject, channel_size, error_throttling_seconds)
    @lock NATS.state.lock begin
        state.handlers[sid] = channel
        state.sub_stats[sid] = sub_stats
        connection.subs[sid] = sub
    end
    send(connection, sub)
    sub
end

# TODO: recactor this
function _start_tasks(f::Function, sub_stats::Stats, conn_stats::Stats, async_handlers::Bool, subject::String, channel_size::Int64, error_throttling_seconds::Float64)
    last_error = nothing
    last_error_msg = nothing
    errors_since_last_log = 0
    handlers_running = Threads.Atomic{Int64}(0)
    lock = ReentrantLock()
    ch = Channel(channel_size)

    if async_handlers == true
        spawn_sticky_task(:default, () -> begin
            try
                while true
                    msg = take!(ch)
                    handler_task = Threads.@spawn :default begin
                        task_local_storage("sub_stats", sub_stats)
                        Threads.atomic_add!(handlers_running, 1)
                        try
                            @inc_stat :handlers_running sub_stats conn_stats state.stats
                            f(msg)
                            @inc_stat :msgs_handled sub_stats conn_stats state.stats
                            @dec_stat :handlers_running sub_stats conn_stats state.stats
                        catch 
                            @inc_stat :msgs_errored sub_stats conn_stats state.stats
                            @dec_stat :handlers_running sub_stats conn_stats state.stats
                            @lock lock begin
                                last_error = err
                                last_error_msg = msg
                                errors_since_last_log = errors_since_last_log + 1
                            end
                        end
                        Threads.atomic_sub!(handlers_running, 1)
                    end
                    async_handlers || wait(handler_task)
                end
            catch err
                err isa InvalidStateException || rethrow()
            end
        end)
    else
        spawn_sticky_task(:default, () -> begin
            task_local_storage("sub_stats", sub_stats)
            try
                while true
                    msg = take!(ch)
                    Threads.atomic_add!(handlers_running, 1)
                    try
                        f(msg)
                        @inc_stat :msgs_handled sub_stats conn_stats state.stats
                    catch err
                        @inc_stat :msgs_errored sub_stats conn_stats state.stats
                        @lock lock begin
                            last_error = err
                            last_error_msg = msg
                            errors_since_last_log = errors_since_last_log + 1
                        end
                    end
                    Threads.atomic_sub!(handlers_running, 1)
                end
            catch err
                err isa InvalidStateException || rethrow()
            end
        end)
    end

    monitor_task = Threads.@spawn :interactive disable_sigint() do
        while isopen(ch)
            sleep(error_throttling_seconds) # TODO: check diff and adjust
            errs, err, msg = @lock lock begin
                errors_since_last_log_save = errors_since_last_log
                errors_since_last_log = 0
                errors_since_last_log_save, last_error, last_error_msg
            end
            if errs > 0
                @error "$errs handler errors on \"$subject\" in last $error_throttling_seconds s." err msg
            end
        end
    end
    errormonitor(monitor_task)

    stats_task = Threads.@spawn :interactive disable_sigint() do
        while isopen(ch) || Base.n_avail(ch) > 0
            if handlers_running.value > 1000
                @warn "$(handlers_running[]) handlers running for subscription on $subject."
            else
                @debug "$(handlers_running[]) handlers running for subscription on $subject."
            end
            level = Base.n_avail(ch) / ch.sz_max
            if level > 0.8
                @warn "Subscription on $subject channel full in $(100 * level) %"
            else
                @debug "Subscription on $subject channel full in $(100 * level) %"
            end
            sleep(20) # TODO: configure it
        end
    end
    errormonitor(stats_task)

    ch
end