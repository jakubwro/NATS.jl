
const DEFAULT_API_CALL_DELAYS = ExponentialBackOff(n = 7, first_delay = 0.1, max_delay = 0.5)

function check_api_call_error(s, e)
    e isa Union{NATS.NATSError, ApiError} && e.code == 503
end

function jetstream_api_call(T, connection::NATS.Connection, subject, data = nothing; delays = DEFAULT_API_CALL_DELAYS)
    call_retry = retry(NATS.request; delays, check = check_api_call_error)
    call_retry(T, connection, subject, data)
end

function jetstream_api_call(f, T, connection::NATS.Connection, subject, data = nothing; delays = DEFAULT_API_CALL_DELAYS)
    NATS.request(connection, subject, data; delays) do res
        if res isa Union{NATS.NATSError, ApiError} && res.code == 503 && !isempty(delays)
            first_delay, rest_of_delays = Iterators.peel(delays)
            sleep(first_delay)
            jetstream_api_call(f, T, connection, subject, data; rest_of_delays)
        else
            f(res)
        end
    end
end
