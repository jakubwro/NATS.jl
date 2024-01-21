

const JETSTREAM_API_CALL_DELAYS = ExponentialBackOff(n = 5, first_delay = 0.2, max_delay = 0.5)

function check_api_response(s, e)
    e isa NATSError && e.code == 503 # No responders indicate leader is down
end

function jetstream_api_call(T::Type{<:ApiResponse}, connection, subject, data)
    response = retry(retries = JETSTREAM_API_CALL_DELAYS, check = check_api_response) do
        req = NATS.request(T, connection, subject, data)
    end
    response
end

function jetstream_api_call(T::Type{Union{<:ApiResponse, ApiError}}, connection, subject, data)
    response = retry(retries = JETSTREAM_API_CALL_DELAYS, check = check_api_response) do
        req = NATS.request(T, connection, subject, data)
    end
    response
end
