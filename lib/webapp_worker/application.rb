require 'socket'

module Process
  class << self
    def alive?(pid)
      begin
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end
    end
  end
end

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
			@mailto = (YAML.load_file(yaml))[@environment]["mailto"] unless @mailto
			@jobs = (YAML.load_file(yaml))[@environment][@hostname] unless @hostname.nil?
		end

		def hostname
			return Socket.gethostname.downcase
		end

		def next_command_run?(til)
			commands = {}
			c = {}
			next_commands = {}

			@jobs.each do |job|
				j = WebappWorker::Job.new(job)
				commands.store(j.command,j.next_run?)
			end
			(commands.sort_by { |key,value| value }).collect { |key,value| c.store(key,value) }

			counter = 0
			c.each do |key,value|
				next_commands.store(key,value)
				counter = counter + 1
				break if counter >= til
			end

			return next_commands
		end

		def check_for_directory
			dir = "/tmp/webapp_worker"

			if Dir.exists?(dir)
			else
				Dir.mkdir(dir, 0700)
			end
		end

		def create_pid
			pid_file = File.open("/tmp/webapp_worker/waw.pid", 'w') { |f| f.write(Process.pid) }
			pid_file.close
		end

		def check_for_process
			self.check_for_directory

			file = "/tmp/webapp_worker/waw.pid"

			if File.exists?(file)
				possible_pid = ""
				pid_file = File.open(file, 'r').each { |f| possible_pid+= f }
				pid_file.close

				if Process.alive?(possible_pid)
				else
					self.create_pid
				end
			end
		end

		def run
			#Going to need to do memory/process management, or fork processes not threads...
			p = Process.fork do
				self.check_for_process

				logger = Logger.new("/tmp/webapp_worker/#{@environment}.log", 5, 5242880)
				logger.level = Logger::INFO

				Signal.trap('HUP', 'IGNORE')

				@threads = {}

				loop do
					@threads.each do |thread,command|
						if thread.status == false
							@threads.delete(thread)
						end
					end

					data = self.next_command_run?(1)

					data.each do |command,time|
						time = time[0]
						now = Time.now.utc
						range = (time - now).to_i

						if @threads.detect { |thr,com| com == command }
							sleep(range) unless range <= 0
						else
							t = Thread.new do
								sleep(range) unless range <= 0
								`#{command}`
							end
							@threads.store(t,command)
						end
					end
				end
			end

			Process.detach(p)
		end

	end
end
