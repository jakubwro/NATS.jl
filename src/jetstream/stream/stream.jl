
struct StreamSub
    subject::String
    sub::NATS.Sub
    consumer::ConsumerInfo
end

function show(io::IO, stream_sub::StreamSub)
    print(io, "StreamSub(\"$(stream_sub.subject)\")")
end


include("manage.jl")
include("info.jl")
include("message.jl")
include("publish.jl")
include("subscribe.jl")
include("unsubscribe.jl")
