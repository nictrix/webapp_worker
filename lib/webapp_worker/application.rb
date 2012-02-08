require 'socket'
require 'timeout'
require 'open4'
require 'drb'

module WebappWorker
	class Application
		attr_accessor :hostname, :mailto, :environment, :jobs, :file, :file_mtime, :pid

		def initialize(user_supplied_hash={})
			standard_hash = { hostname:"#{self.hostname}", mailto:nil, environment:"local", jobs:"", file:nil, file_mtime:nil, pid:nil }

			user_supplied_hash = {} unless user_supplied_hash
			user_supplied_hash = standard_hash.merge(user_supplied_hash)

			user_supplied_hash.each do |key,value|
				self.instance_variable_set("@#{key}", value)
				self.class.send(:define_method, key, proc{self.instance_variable_get("@#{key}")})
				self.class.send(:define_method, "#{key}=", proc{|x| self.instance_variable_set("@#{key}", x)})
			end
		end

		def parse_yaml(yaml)
			@file = yaml
			@file_mtime = File.mtime(@file) if File.exists?(@file)
			@mailto = (YAML.load_file(@file))[@environment]["mailto"] unless @mailto

			begin
				@jobs = (YAML.load_file(@file))[@environment][@hostname] unless @hostname.nil?
			rescue => error
				puts error
			end
		end

		def hostname
			return Socket.gethostname.downcase
		end

		def check_file_modification_time
			if @file != nil
				mtime = File.mtime(@file) if File.exists?(@file)

				if mtime != @file_mtime
					@file_mtime = mtime
					self.parse_yaml(@file)
				end
			end
		end

		def next_command_run?(til)
			commands = {}
			c = {}
			next_commands = {}
			new_jobs = []

			(0..til).each do |i|
				@jobs.each do |j|
					new_jobs << j
				end
			end

			new_jobs.flatten.each do |job|
				j = WebappWorker::Job.new(job)
				commands.store(j.command,j.next_runs?(til))
			end

			(commands.sort_by { |key,value| value }).collect { |key,value| c.store(key,value) }

			counter = 0
			c.each do |key,value|
				next_commands.store(key,value)
				counter = counter + 1
				break if counter >= @jobs.length
			end

			return next_commands
		end

		def next_command_run_time?
			commands = {}
			c = {}

			@jobs.each do |job|
				j = WebappWorker::Job.new(job)
				commands.store(j.command,j.next_run?)
			end
			(commands.sort_by { |key,value| value }).collect { |key,value| c.store(key,value) }

			c.each do |key,value|
				return value[0]
			end
		end

		def commands_to_run
			self.check_file_modification_time

			commands = {}
			c = {}
			next_commands = {}

			@jobs.each do |job|
				j = WebappWorker::Job.new(job)
				commands.store(j.command,j.next_run?)
			end
			(commands.sort_by { |key,value| value }).collect { |key,value| c.store(key,value) }

			c.each do |key,value|
				next_commands.store(key,value)
			end

			return next_commands
		end

		def run_job(job=nil)
			ipc_file = "/tmp/webapp_worker/jobs"

			if job
				begin
					on_demand_jobs = DRbObject.new(nil,"drbunix:#{ipc_file}")
					on_demand_jobs << job
					puts "Sent on demand job"
				rescue => error
					puts "Error sending new job: #{error}"
				end
			end
		end

		def self.run_command(time,command,logger)
			now = Time.now.utc
			range = (time - now).to_i
			@pid = ""

			t = Thread.new do
				logger.debug "Creating New Thread for command: #{command} - may need to sleep for: #{range} seconds"
				sleep(range) unless range <= 0
				logger.debug "Running Command: #{command}"

				pid, stdin, stdout, stderr = Open4::popen4 command
				@pid = pid

				#make logger log to a specific job file log file

				ignored, status = Process::waitpid2 pid

				if status.to_i == 0
					logger.debug "Completed Command: #{command}"
				else
					logger.fatal "Command: #{command} Failure! Exited with Status: #{status.to_i}, Standard Out and Error Below"
					logger.fatal "STDOUT BELOW:"
					stdout.each_line do |line|
						logger.fatal line
					end
					logger.fatal "STDERR BELOW:"
					stderr.each_line do |line|
						logger.fatal line
					end
					logger.fatal "Command: #{command} Unable to Complete! Standard Out and Error Above"
				end
			end

			return t, @pid
		end

		def run(debug=nil,verbose=nil)
			p = Process.fork do
				#Some Setup Work
				$0="WebApp Worker - Job File: #{@file || 'No File'}"
				waw_system = WebappWorker::System.new
				waw_system.setup(debug,verbose)
				logger = waw_system.logger

				%w(INT QUIT TERM TSTP).each do |sig|
					Signal.trap(sig) do
						stop_loop = true
						logger.warn "Received a #{sig} signal, stopping current commands."
						waw_system.graceful_termination(@threads,@command_processes)
					end
				end

				Thread.new do
					ipc_file = "/tmp/webapp_worker/jobs"
					@on_demand_commands = []
					begin
						logger.info "Starting to listen on IPC for New Application Jobs: #{ipc_file}"
						DRb.start_service("drbunix:#{ipc_file}", @on_demand_commands)
						logger.info "Now listening on IPC: #{ipc_file}"
					rescue => error
						logger.fatal "Error at New Application Jobs IPC Start Listening: #{error}"
					end

					loop do
						if @on_demand_commands
							@on_demand_commands.each do |c|
								Application.run_command(Time.now,c,logger)
								@on_demand_commands.delete_at(c)
							end
						end
					end
				end

				#WebApp Worker is setup now do the real work
				@command_processes = {}
				@threads = {}
				stop_loop = false

				logger.debug "Going into Loop"
				until stop_loop
					@threads.each do |thread,command|
						if thread.status == false
							logger.debug "Deleting Old Thread from Array of Jobs"
							@threads.delete(thread)
						end
					end

					data = self.commands_to_run

					data.each do |command,time|
						if @threads.detect { |thr,com| com == command }
							data.delete(command)
						else
							run_command = Application.run_command(time[0],command,logger)
							command_thread = run_command[0]
							pid = run_command[1]

							@command_processes.store(pid,command)
							@threads.store(command_thread,command)
						end
					end

					logger.debug Thread.list
					logger.debug @threads.inspect
					logger.debug @command_processes.inspect

					time = self.next_command_run_time?
					now = Time.now.utc
					range = (time - now).to_i
					range = range - 1
					logger.debug "Sleeping for #{range} seconds after looping through all jobs found"
					sleep(range) unless range <= 0
				end
			end

			@pid = p.to_i
			Process.detach(p)
		end
	end
end
