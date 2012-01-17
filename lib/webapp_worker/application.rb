require 'socket'
require 'timeout'
require 'open4'
require 'drb'
require 'logger'

module WebappWorker
	class Application
		attr_accessor :hostname, :mailto, :environment, :jobs, :file, :file_mtime

		def initialize(user_supplied_hash={})
			standard_hash = { hostname:"#{self.hostname}", mailto:"", environment:"local", jobs:"", file:"" }

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
			@file_mtime = File.mtime(@file)
			@mailto = (YAML.load_file(@file))[@environment]["mailto"] unless @mailto
			@jobs = (YAML.load_file(@file))[@environment][@hostname] unless @hostname.nil?
		end

		def hostname
			return Socket.gethostname.downcase
		end

		def check_file_modification_time
			mtime = File.mtime(@file)

			if mtime != @file_mtime
				@file_mtime = mtime
				self.parse_yaml(@file)
			end
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

		def graceful_termination(logger)
			stop_loop = true

			begin
				puts
				puts "Graceful Termination started, waiting 60 seconds before KILL signal send"
				logger.info "Graceful Termination started, waiting 60 seconds before KILL signal send"

				Timeout::timeout(60) do
					@command_processes.each do |pid,command|
						logger.debug "Sending INT Signal to #{command} Process with PID: #{pid}"

						if WebappWorker::System.process_alive?(pid)
							Process.kill("INT",pid.to_i)
						end
					end

					@threads.each do |thread,command|
						thread.join
					end
				end
			rescue Timeout::Error
				puts "Graceful Termination bypassed, killing processes and threads"
				logger.info "Graceful Termination bypassed, killing processes and threads"

				@command_processes.each do |pid,command|
					logger.debug "Killing #{command} Process with PID: #{pid}"
					begin
						Process.kill("KILL",pid.to_i)
					rescue => error
					end
				end

				@threads.each do |thread,command|
					logger.debug "Killing Command Thread: #{command}"
					Thread.kill(thread)
				end
			end

			puts "Stopping Webapp Worker"
			logger.info "Stopping Webapp Worker"
			file = "/tmp/webapp_worker/waw.pid"
			File.delete(file)
			exit 0
		end

		def run(debug=nil,verbose=nil)
			p = Process.fork do
				$0="Web App Worker - Job File: #{@file}"
				waw_system = WebappWorker.new
				waw_system.setup(debug,verbose)
				logger = waw_system.logger

				@command_processes = {}
				@threads = {}
				stop_loop = false

				Signal.trap('HUP', 'IGNORE')

				%w(INT QUIT TERM TSTP).each do |sig|
					Signal.trap(sig) do
						logger.warn "Received a #{sig} signal, stopping current commands."
						self.graceful_termination(logger)
					end
				end

				Signal.trap('USR1') do
					version = WebappWorker::VERSION
					puts
					puts "Webapp Worker Version: #{version}"
					logger.info "Received USR1 signal, sent version: #{version}"
				end

				Signal.trap('USR2') do
					logger.level = Logger::DEBUG
					puts
					puts "Changed logger level to Debug"
					logger.info "Changed logger level to Debug"
				end

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
						time = time[0]
						now = Time.now.utc
						range = (time - now).to_i

						if @threads.detect { |thr,com| com == command }
							data.delete(command)
						else
							t = Thread.new do
								logger.debug "Creating New Thread for command: #{command} - may need to sleep for: #{range} seconds"
								sleep(range) unless range <= 0
								logger.debug "Running Command: #{command}"

								pid, stdin, stdout, stderr = Open4::popen4 command
								@command_processes.store(pid,command)

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
							@threads.store(t,command)
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

			Process.detach(p)
		end

	end
end
