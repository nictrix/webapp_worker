require 'socket'
require 'logger'

module Process
  class << self
    def alive?(pid)
      begin
        Process.kill(0, pid.to_i)
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

		def create_pid(logger)
			logger.info "Creating Pid File at /tmp/webapp_worker/waw.pid"

			File.open("/tmp/webapp_worker/waw.pid", 'w') { |f| f.write(Process.pid) }

			logger.info "Pid File created: #{Process.pid} at /tmp/webapp_worker/waw.pid"
		end

		def check_for_process(logger)
			file = "/tmp/webapp_worker/waw.pid"

			if File.exists?(file)
				possible_pid = ""
				pid_file = File.open(file, 'r').each { |f| possible_pid+= f }
				pid_file.close

				if Process.alive?(possible_pid)
					puts "Already found webapp_worker running, pid is: #{possible_pid}, exiting..."
					logger.fatal "Found webapp_worker already running with pid: #{possible_pid}, Pid File: #{file}, exiting..."
					exit 1
				else
					File.delete(file)
					self.create_pid(logger)
				end
			else
				self.create_pid(logger)
			end

			logger.info "Starting Webapp Worker"
		end

		def run
			self.check_for_directory

			logger = Logger.new("/tmp/webapp_worker/#{@environment}.log", 5, 5242880)
			logger.level = Logger::INFO

			p = Process.fork do
				begin
					self.check_for_process(logger)
				rescue => error
					puts error.inspect
					logger.fatal error.inspect
				end

				@threads = {}

				stop_loop = false
				Signal.trap('HUP', 'IGNORE')
				Signal.trap('INT') do
					stop_loop = true
					logger.warn "Recieved an INT Signal, stopping loop. Check last log message, we may have to wait for that sleep!"
				end

				logger.info "Going into Loop"
				until stop_loop
					@threads.each do |thread,command|
						if thread.status == false
							logger.info "Deleting Old Thread from Array of Jobs"
							@threads.delete(thread)
						end
					end

					data = self.next_command_run?(1)

					data.each do |command,time|
						time = time[0]
						now = Time.now.utc
						range = (time - now).to_i

						if @threads.detect { |thr,com| com == command }
							logger.info "Already found command in a thread: #{command}, sleeping for: #{range} seconds"
							sleep(range) unless range <= 0
						else
							t = Thread.new do
								logger.info "Creating New Thread for command: #{command} - may need to sleep for: #{range} seconds"
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
