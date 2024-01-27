
struct StreamSub
    sub::NATS.Sub
    consumer::ConsumerInfo
end


include("manage.jl")
include("info.jl")
include("message.jl")
include("publish.jl")
include("subscribe.jl")
include("unsubscribe.jl")
