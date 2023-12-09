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
- `monitoring_throttle_seconds`: time intervals in seconds that handler errors will be reported in logs, default is `$SUBSCRIPTION_ERROR_THROTTLING_SECONDS` seconds
"""
function subscribe(
    f,
    subject::String;
    connection::Connection = connection(:default),
    queue_group::Union{String, Nothing} = nothing,
    async_handlers = false,
    channel_size = SUBSCRIPTION_CHANNEL_SIZE,
    monitoring_throttle_seconds = SUBSCRIPTION_ERROR_THROTTLING_SECONDS
)
    arg_t = argtype(f)
    find_msg_conversion_or_throw(arg_t)
    f_typed = _fast_call(f, arg_t)
    sid = new_sid(connection)
    sub = Sub(subject, queue_group, sid)
    sub_stats = Stats()
    channel = _start_tasks(f_typed, sub_stats, connection.stats, async_handlers, subject, channel_size, monitoring_throttle_seconds)
    @lock NATS.state.lock begin
        state.handlers[sid] = channel
        state.sub_stats[sid] = sub_stats
        connection.subs[sid] = sub
    end
    send(connection, sub)
    sub
end

@kwdef mutable struct SubscriptionMonitoringData
    last_error::Union{ErrorException, Nothing} = nothing
    last_error_msg::Union{Msg, Nothing} = nothing
    errors_since_last_report::Int64 = 0
    lock::ReentrantLock = Threads.ReentrantLock()
end

function report_error!(data::SubscriptionMonitoringData, err::ErrorException, msg::Msg)
    @lock data.lock begin
        data.last_error = err
        data.last_error_msg = msg
        data.errors_since_last_report += 1
    end
end

# Resets errors counter and obtains current state.
function reset_counter!(data::SubscriptionMonitoringData)
    @lock data.lock begin
        save = data.errors_since_last_report
        data.errors_since_last_report = 0
        save, data.last_error, data.last_error_msg
    end
end

# TODO: recactor this
function _start_tasks(f::Function, sub_stats::Stats, conn_stats::Stats, async_handlers::Bool, subject::String, channel_size::Int64, monitoring_throttle_seconds::Float64)
    subscription_channel = Channel(channel_size)
    monitoring_data = SubscriptionMonitoringData()
    if async_handlers == true
        Threads.@spawn :interactive disable_sigint() do
            try
                while true
                    msgs = take!(subscription_channel)
                    for msg in msgs # TODO: vectoriztion
                        handler_task = Threads.@spawn :default disable_sigint() do
                            task_local_storage("sub_stats", sub_stats)
                            try
                                @inc_stat :handlers_running 1 sub_stats conn_stats state.stats
                                f(msg)
                                @inc_stat :msgs_handled 1 sub_stats conn_stats state.stats
                                @dec_stat :handlers_running 1 sub_stats conn_stats state.stats
                            catch 
                                @inc_stat :msgs_errored 1 sub_stats conn_stats state.stats
                                @dec_stat :handlers_running 1 sub_stats conn_stats state.stats
                                report_error!(monitoring_data, err, msg)
                            end
                        end
                    end
                end
            catch err
                err isa InvalidStateException || rethrow()
            end
        end
    else
        Threads.@spawn :default disable_sigint() do
            task_local_storage("sub_stats", sub_stats)
            try
                while true
                    msgs = take!(subscription_channel)
                    for msg in msgs # TODO do some vectorization
                        try
                            @inc_stat :handlers_running 1 sub_stats conn_stats state.stats
                            f(msg)
                            @inc_stat :msgs_handled 1 sub_stats conn_stats state.stats
                            @dec_stat :handlers_running 1 sub_stats conn_stats state.stats
                        catch err
                            @dec_stat :handlers_running 1 sub_stats conn_stats state.stats
                            @inc_stat :msgs_errored 1 sub_stats conn_stats state.stats
                            report_error!(monitoring_data, err, msg)
                        end
                    end
                end
            catch err
                err isa InvalidStateException || rethrow()
            end
        end
    end

    subscription_monitoring_task = Threads.@spawn :interactive begin
        while isopen(subscription_channel) || Base.n_avail(subscription_channel) > 0
            sleep(monitoring_throttle_seconds)
            # Warn about too many handlers running.
            handlers_running = sub_stats.handlers_running
            if handlers_running > 1000 # TODO: add to config.
                @warn "$(handlers_running) handlers running for subscription on $subject."
            end
            # Warn if subscription channel is too small.
            level = Base.n_avail(subscription_channel) / subscription_channel.sz_max
            if level > 0.8 # TODO: add to config.
                @warn "Subscription on $subject channel full in $(100 * level) %"
            end
            # Report errors thrown by the handler function.
            errs, err, msg = reset_counter!(monitoring_data)
            if errs > 0
                @error "$errs handler errors on \"$subject\" in last $monitoring_throttle_seconds s." err msg
            end

        end
        @debug "Subscription monitoring task finished."
    end
    errormonitor(subscription_monitoring_task)

    subscription_channel
end