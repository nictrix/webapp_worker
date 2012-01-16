require 'socket'
require 'timeout'
require 'open4'
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

		def check_file_modification_time
			mtime = File.mtime(@file)

			if mtime != @file_mtime
				@file_mtime = mtime
				self.parse_yaml(@file)
			end
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
			$0="Web App Worker - Job File: #{@file}"

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
					logger.fatal "Found webapp_worker already running with pid: #{possible_pid}, Pid File: #{file} exiting..."
					exit 1
				else
					logger.warn "Found pid file, but no process running, recreating pid file with my pid: #{Process.pid}"
					File.delete(file)
					self.create_pid(logger)
				end
			else
				self.create_pid(logger)
			end

			logger.info "Starting Webapp Worker"
		end

		def graceful_termination(logger)
			stop_loop = true

			begin
				logger.info "Graceful Termination started, waiting 60 seconds before KILL signal sent"

				Timeout::timeout(60) do
					@command_processes.each do |pid,command|
						logger.debug "Sending INT Signal to #{command} Process with PID: #{pid}"
						begin
							Process.kill("INT",pid.to_i)
						rescue => error
						end
					end

					@threads.each do |thread,command|
						thread.join
					end
				end
			rescue Timeout::Error
				logger.info "Timeout while trying joining threads, killing threads"

				@command_processes.each do |pid,command|
					logger.debug "Killing #{command} Process with PID: #{pid}"
					Process.kill("KILL",pid.to_i)
				end

				@threads.each do |thread,command|
					logger.debug "Killing Command Thread: #{command}"
					Thread.kill(thread)
				end
			end

			logger.info "Stopping Webapp Worker"
			file = "/tmp/webapp_worker/waw.pid"
			File.delete(file)
			exit 0
		end

		def run
			self.check_for_directory

			logger = Logger.new("/tmp/webapp_worker/#{@environment}.log", 5, 5242880)
			logger.level = Logger::DEBUG

			p = Process.fork do
				begin
					self.check_for_process(logger)
				rescue => error
					puts error.inspect
					logger.fatal error.inspect
				end

				@command_processes = {}
				@threads = {}
				stop_loop = false

				Signal.trap('HUP', 'IGNORE')

				%w(INT QUIT TERM TSTP).each do |sig|
					Signal.trap(sig) do
						logger.warn "Recieved a #{sig} signal, stopping current commands."
						self.graceful_termination(logger)
					end
				end

				Signal.trap('STOP') do |s|
					#Stop Looping until
					stop_loop = true
					logger.warn "Recieved signal #{s}, pausing current loop."
				end

				Signal.trap('CONT') do
					#Start Looping again (catch throw?)
					stop_loop = false
					logger.warn "Recieved signal #{s}, starting current loop."
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
