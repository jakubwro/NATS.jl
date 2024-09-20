using NATS, Test
using JSON3

@testset "Scoped connections" begin
    @test_throws ErrorException publish("some.random.subject")

    sc = NATS.connect()
    was_delivered = false
    with_connection(sc) do 
        sub = subscribe("subject_1") do msg
            was_delivered = true
        end
        publish("subject_1")
        publish("subject_1", "Some data")
        drain(sub)
    end
    @test was_delivered == true

    with_connection(sc) do 
        sub = reply("service_1") do 
            "Response content"
        end
        answer = request("service_1")
        @test payload(answer) == "Response content"
        answer = request(String, "service_1")
        @test answer == "Response content"
        sub2 = reply("service_1") do 
            "Response content 2"
        end
        answers = request(2, "service_1", nothing)
        @test length(answers) == 2
        drain(sub)
        drain(sub2)
    end
    drain(sc)
    sc = NATS.connect()
    with_connection(sc) do 
        sub1 = reply("some_service") do 
            "Response content"
        end
        sub2 = reply("some_service") do 
            "Response content"
        end
        unsubscribe(sub1)
        unsubscribe(sub2.sid)
    end
    drain(sc)
end

@testset "Scoped connections sync subscriptions" begin
    sc = NATS.connect()

    with_connection(sc) do 
        sub = subscribe("subject_1")

        publish("subject_1", "test")
        msg = next(sub)
        @test msg isa NATS.Msg
        
        publish("subject_1", "{}")
        msg = next(JSON3.Object, sub)
        @test msg isa JSON3.Object

        publish("subject_1", "test")
        msgs = next(sub, 1)
        @test msgs isa Vector{NATS.Msg}
        @test length(msgs) == 1

        publish("subject_1", "{}")
        jsons = next(JSON3.Object, sub, 1)
        @test jsons isa Vector{JSON3.Object}
        @test length(jsons) == 1

        drain(sub)
    end
end
