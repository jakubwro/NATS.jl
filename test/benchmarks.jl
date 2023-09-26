using Test
using Random
using NATS

# [ Info: Received 208059 messages in 10.0 s, 20805.9 msgs / s.
# === Connection status ====================
# connections:    1        
#   [#1]:  CONNECTED, 0 subs, 0 unsubs, 9619 outbox             
# subscriptions:  0           
# msgs_handled:   208059         
# msgs_unhandled: 113        
# ==========================================
@testset "Msgs per second." begin
    nc = NATS.connect()
    empty!(NATS.state.fallback_handlers)
    c = Channel(1000000)
    subject = "SOME_SUBJECT"
    time_to_wait_s = 10.0
    tm = Timer(time_to_wait_s)
    sub = subscribe(subject) do msg
        if isopen(tm)
            try put!(c, msg) catch err @error err end
        end
    end
    t = Threads.@spawn :default begin
        n = 0
        while isopen(tm)
            if Base.n_avail(c) < n - 10000
                sleep(0.001)
            else
                publish(subject; payload = "Hi!")
                n = n + 1
            end
        end
        unsubscribe(sub)
    end
    @async NATS.istatus(tm)
    wait(t)
    received = Base.n_avail(c)
    @info "Received $received messages in $time_to_wait_s s, $(received / time_to_wait_s) msgs / s."
    NATS.status()
end

