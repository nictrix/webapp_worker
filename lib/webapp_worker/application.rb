module WebappWorker
	class Application
		def run
		end
	end
end

if __FILE__ == $0
	j = WebappWorker::Job.new
	j.minute = 59
	puts j.inspect
	puts j.next_run?

	j = WebappWorker::Job.new(command:"hostname",minute:"*",day:"0-16/3",month:7,weekday:2)
	puts j.inspect
	puts j.next_runs?(20)

	j = WebappWorker::Job.new_from_yaml("--- \n:command: rake job:run\n:minute: 0-59/5\n:hour: 0-4/2\n:day: 1\n:month: 0-12/1\n")
	puts j.inspect
	puts j.next_runs?(14)
end
