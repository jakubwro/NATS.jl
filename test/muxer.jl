using Test
using NATS
using Random
using NATS.JetStream

@testset "Request muxer" begin

    @testset "Muxer is lazy and reused" begin
        conn = NATS.connect()
        sleep(1)
        try
            # No reply subscription exists until the first request.
            @test isnothing(conn.reply_subject)

            sub = reply(conn, "MUX.REUSE") do msg; "pong: " * payload(msg) end
            sleep(0.5)
            @test isnothing(conn.reply_subject)

            @test payload(request(conn, "MUX.REUSE", "a")) == "pong: a"
            @test !isnothing(conn.reply_subject)
            @test startswith(conn.reply_subject, NATS.DEFAULT_INBOX_PREFIX)

            prefix = conn.reply_subject
            nsubs = length(conn.sub_data)

            # Further requests must not create subscriptions.
            for i in 1:100
                @test payload(request(conn, "MUX.REUSE", string(i))) == "pong: $i"
            end
            @test conn.reply_subject == prefix
            @test length(conn.sub_data) == nsubs
            @test NATS.pending_requests(conn) == 0

            drain(conn, sub)
        finally
            drain(conn)
        end
    end

    @testset "Concurrent requests are routed to the right caller" begin
        conn = NATS.connect()
        sleep(1)
        try
            # Echo service: a mismatch means replies were cross wired.
            sub = reply(conn, "MUX.ECHO") do msg; payload(msg) end
            sleep(0.5)

            n = 500
            results = Vector{Union{String, Nothing}}(nothing, n)
            @sync for i in 1:n
                Threads.@spawn begin
                    results[i] = payload(request(conn, "MUX.ECHO", string(i); timeout = 30))
                end
            end
            @test results == string.(1:n)
            @test NATS.pending_requests(conn) == 0
            # Only the echo subscription and the muxer subscription.
            @test length(conn.sub_data) == 2

            drain(conn, sub)
        finally
            drain(conn)
        end
    end

    @testset "Muxer is created once under a concurrent first request" begin
        conn = NATS.connect()
        sleep(1)
        try
            sub = reply(conn, "MUX.RACE") do msg; "ok" end
            sleep(0.5)

            # All of these race to initialize the muxer at the same time.
            oks = fill(false, 50)
            @sync for i in 1:50
                Threads.@spawn begin
                    oks[i] = payload(request(conn, "MUX.RACE"; timeout = 30)) == "ok"
                end
            end
            @test all(oks)
            @test length(conn.sub_data) == 2
            @test NATS.pending_requests(conn) == 0

            drain(conn, sub)
        finally
            drain(conn)
        end
    end

    @testset "Timeout releases the registration" begin
        conn = NATS.connect()
        sleep(1)
        try
            # Replier is far slower than the request timeout.
            sub = subscribe(conn, "MUX.SLOW") do msg; sleep(10) end
            sleep(0.5)

            start = time()
            @test_throws NATSError request(conn, "MUX.SLOW", "x"; timeout = 0.5)
            # Must give up on its own timeout, not wait for the handler.
            @test time() - start < 5.0
            @test NATS.pending_requests(conn) == 0

            NATS.unsubscribe(conn, sub)
        finally
            drain(conn)
        end
    end

    @testset "Surplus replies do not stall the muxer" begin
        conn = NATS.connect()
        sleep(1)
        try
            subject = randstring(10)
            # Three responders, but only one reply is requested. The extra two
            # must be dropped rather than blocking the muxer task.
            subs = [reply(conn, subject) do msg; "r" end for _ in 1:3]
            sleep(0.5)

            @test length(request(conn, 1, subject, "go")) == 1
            sleep(0.5)
            @test NATS.pending_requests(conn) == 0

            # The connection must still serve requests afterwards.
            after = reply(conn, "MUX.AFTER") do msg; "ok" end
            sleep(0.5)
            @test payload(request(conn, "MUX.AFTER"; timeout = 10)) == "ok"

            drain(conn, after)
            for s in subs; drain(conn, s); end
        finally
            drain(conn)
        end
    end

    @testset "Muxer survives a reconnect" begin
        conn = NATS.connect()
        sleep(1)
        try
            sub = reply(conn, "MUX.RECONNECT") do msg; "ok" end
            sleep(0.5)
            @test payload(request(conn, "MUX.RECONNECT")) == "ok"
            prefix = conn.reply_subject
            sid = conn.reply_sub.sid

            NATS.reconnect(conn)
            sleep(3)
            @test NATS.status(conn) == NATS.CONNECTED

            # The subscription is replayed from `sub_data`, so the inbox prefix
            # stays valid and replies keep routing.
            @test conn.reply_subject == prefix
            @test conn.reply_sub.sid == sid
            @test payload(request(conn, "MUX.RECONNECT"; timeout = 15)) == "ok"
            @test NATS.pending_requests(conn) == 0

            drain(conn, sub)
        finally
            drain(conn)
        end
    end

    @testset "Drain wakes a blocked request" begin
        conn = NATS.connect()
        sleep(1)
        # Nobody ever replies, and the timeout is far longer than the test.
        sub = subscribe(conn, "MUX.NEVER") do msg; sleep(60) end
        sleep(0.5)
        task = Threads.@spawn begin
            try
                request(conn, "MUX.NEVER", "x"; timeout = 120)
                :returned
            catch
                :threw
            end
        end
        sleep(1.0)

        start = time()
        drain(conn)
        @test fetch(task) == :threw
        # Unblocked by the drain, not by its own timeout.
        @test time() - start < 30
        @test NATS.pending_requests(conn) == 0
        @test NATS.status(conn) == NATS.DRAINED
    end

    # A JetStream pull consumer replies with a stored message, which carries
    # the *stream* subject, a `$JS.ACK...` reply_to and no header naming the
    # inbox. Nothing in it identifies the request, so it cannot be routed by
    # the shared wildcard subscription and must use a dedicated inbox.
    @testset "JetStream pull consumers are not muxed" begin
        conn = NATS.connect()
        sleep(1)
        try
            @test NATS.request_dedicated_inbox("\$JS.API.CONSUMER.MSG.NEXT.S.C")
            @test !NATS.request_dedicated_inbox("\$JS.API.STREAM.INFO.S")
            @test !NATS.request_dedicated_inbox("SOME.SERVICE")

            stream = "MUXJS" * randstring(6)
            subject = "muxjs." * randstring(5)
            info = stream_create(conn, StreamConfiguration(
                name = stream, subjects = [subject], storage = :memory))
            try
                for i in 1:10
                    JetStream.stream_publish(conn, subject, "msg-$i")
                end
                consumer = consumer_create(conn, ConsumerConfiguration(
                    name = "c" * randstring(6), ack_policy = :explicit), info)

                # This deadlocked when pull replies were routed by subject.
                received = String[]
                for _ in 1:10
                    msg = consumer_next(conn, consumer)
                    push!(received, payload(msg))
                    consumer_ack(conn, msg)
                end
                @test received == ["msg-$i" for i in 1:10]
                @test NATS.pending_requests(conn) == 0
            finally
                stream_delete(conn, stream)
            end
        finally
            drain(conn)
        end
    end

    # Regular JetStream API calls do reply on the inbox, so they stay muxed.
    @testset "JetStream API calls stay muxed" begin
        conn = NATS.connect()
        sleep(1)
        try
            stream = "MUXAPI" * randstring(6)
            subject = "muxapi." * randstring(5)
            stream_create(conn, StreamConfiguration(
                name = stream, subjects = [subject], storage = :memory))
            try
                info = JetStream.stream_info(conn, stream)
                @test info.config.name == stream
                # Only the muxer subscription, no dedicated inbox was needed.
                @test length(conn.sub_data) == 1
                @test NATS.is_muxer_sub(conn, only(keys(conn.sub_data)))
                @test NATS.pending_requests(conn) == 0
            finally
                stream_delete(conn, stream)
            end
        finally
            drain(conn)
        end
    end
end
