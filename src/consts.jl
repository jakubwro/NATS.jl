
const NATS_CLIENT_VERSION = "0.1.0"
const NATS_CLIENT_LANG = "julia"
const NATS_HOST = get(ENV, "NATS_HOST", "localhost")
const NATS_PORT = parse(Int, get(ENV, "NATS_PORT", "4222"))
const DEFAULT_CONNECT_ARGS = (
    verbose= false,
    pedantic = false,
    tls_required = false,
    auth_token = nothing,
    user = nothing,
    pass = nothing,
    name = nothing,
    lang = NATS_CLIENT_LANG,
    version = NATS_CLIENT_VERSION,
    protocol = nothing,
    echo = nothing,
    sig = nothing,
    jwt = nothing,
    no_responders = true,
    headers = true,
    nkey = nothing
)
const OUTBOX_SIZE = 10000000
const SOCKET_CONNECT_DELAYS = Base.ExponentialBackOff(n=1000, first_delay=0.5, max_delay=1)
const SUBSCRIPTION_CHANNEL_SIZE = 10000

const MIME_PROTOCOL = MIME"application/nats"
const MIME_PAYLOAD  = MIME"application/nats-payload"
const MIME_HEADERS  = MIME"application/nats-headers"
