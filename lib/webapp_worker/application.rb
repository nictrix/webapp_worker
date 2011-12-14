require 'socket'

module WebappWorker
	class Application
		attr_accessor :hostname, :mailto, :environment, :jobs

		def initialize(user_supplied_hash={})
			standard_hash = { hostname:"#{self.hostname}", mailto:"", environment:"local", jobs:"" }

			user_supplied_hash = {} unless user_supplied_hash
			user_supplied_hash = standard_hash.merge(user_supplied_hash)

			user_supplied_hash.each do |key,value|
				self.instance_variable_set("@#{key}", value)
				self.class.send(:define_method, key, proc{self.instance_variable_get("@#{key}")})
				self.class.send(:define_method, "#{key}=", proc{|x| self.instance_variable_set("@#{key}", x)})
			end
		end

		def parse_yaml(yaml)
			@mailto = (YAML.load_file(yaml))[@environment]["mailto"]
			@jobs = (YAML.load_file(yaml))[@environment][@hostname]
		end

		def hostname
			return Socket.gethostname.downcase
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
