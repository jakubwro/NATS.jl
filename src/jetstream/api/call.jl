
const DEFAULT_API_CALL_DELAYS = ExponentialBackOff(n = 7, first_delay = 0.1, max_delay = 0.5)

function check_api_call_error(s, e)
    e isa Union{NATS.NATSError, ApiError} && e.code == 503
end

function jetstream_api_call(T, connection::NATS.Connection, subject, data = nothing; delays = DEFAULT_API_CALL_DELAYS)
    call_retry = retry(NATS.request; delays, check = check_api_call_error)
    call_retry(T, connection, subject, data)
end
