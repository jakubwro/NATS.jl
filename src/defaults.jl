
const NATS_CLIENT_VERSION = "0.1.0"
const NATS_CLIENT_LANG = "julia"
const NATS_DEFAULT_HOST = "localhost"
const NATS_DEFAULT_PORT = 4222
const DEFAULT_CONNECT_ARGS = (
    verbose= true,
    pedantic = true,
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
    no_responders = nothing,
    headers = nothing,
    nkey = nothing
)
const OUTBOX_SIZE = 1000000

