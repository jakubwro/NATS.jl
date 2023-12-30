using NATS, Test

@testset "Scoped connections" begin
    @test_throws KeyError publish("some.random.subject")

    sc = NATS.connect()
    was_delivered = false
    with_connection(sc) do 
        sub = subscribe("subject_1") do msg
            was_delivered = true
        end
        publish("subject_1")
        publish("subject_1", "Some data") 
        sleep(0.1)
        unsubscribe(sub)
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
        answers = request("service_1", nothing, 2)
        @test length(answers) == 2
        unsubscribe(sub.sid)
        unsubscribe(sub2.sid)
    end
end
