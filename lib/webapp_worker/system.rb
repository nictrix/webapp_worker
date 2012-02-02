require 'drb'
require 'etc'
require 'logger'

module WebappWorker
	class System

		attr_accessor :user, :tmp_dir, :pid_file, :ipc_file, :logger

		def initialize(user_supplied_hash={})
			standard_hash = { user:"nobody", tmp_dir:"/tmp/webapp_worker/", pid_file:"/tmp/webapp_worker/waw.pid", ipc_file:"/tmp/webapp_worker/waw", logger:"" }

			user_supplied_hash = {} unless user_supplied_hash
			user_supplied_hash = standard_hash.merge(user_supplied_hash)

			user_supplied_hash.each do |key,value|
				self.instance_variable_set("@#{key}", value)
				self.class.send(:define_method, key, proc{self.instance_variable_get("@#{key}")})
				self.class.send(:define_method, "#{key}=", proc{|x| self.instance_variable_set("@#{key}", x)})
			end
		end

    def self.process_alive?(pid)
      begin
        Process.kill(0, pid.to_i)
        true
      rescue Errno::ESRCH
        false
      end
    end

    def setup(debug=nil,verbose=nil)
      self.check_for_directory
      self.create_logger(debug,verbose)
      self.check_for_process
      self.start_listening

      Signal.trap('HUP', 'IGNORE')

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
    end

		def check_for_directory
			if Dir.exists?(@tmp_dir)
			else
				Dir.mkdir(@tmp_dir, 0700)
			end
		end

    def create_logger(debug=nil,verbose=nil)
      @logger = Logger.new("#{@tmp_dir}waw.log", 5, 5242880)

      if debug
        @logger.level = Logger::DEBUG
      elsif verbose
        @logger.level = Logger::INFO
      else
        @logger.level = Logger::WARN
      end
    end

    def delete_files
      @logger.fatal "Deleting both PID and IPC files"

      begin
				File.delete(@pid_file) if File.exists?(@pid_file)
        @logger.fatal "Deleted PID File: #{@pid_file}"
      rescue => error
        @logger.fatal "Error at Deleting PID File: #{@pid_file}: #{error}"
      end

      begin
				File.delete(@ipc_file) if File.exists?(@ipc_file)
        @logger.fatal "Deleted IPC File: #{@ipc_file}"
      rescue => error
        @logger.fatal "Error at Deleting IPC File: #{@ipc_file}: #{error}"
      end
    end

		def create_pid
      self.delete_files

			begin
				@logger.info "Creating Pid File at #{@pid_file}"
				File.open(@pid_file, 'w') { |f| f.write(Process.pid) }
				@logger.info "Pid File created: #{Process.pid} at #{@pid_file}"
			rescue => error
				@logger.fatal "Error creating PID file: #{error}"
			end
		end

		def check_for_process
			if File.exists?(@pid_file)
				possible_pid = ""
				pf = File.open(@pid_file, 'r').each { |f| possible_pid+= f }
				pf.close

				if WebappWorker::System.process_alive?(possible_pid)
          version = self.check_process_version
          my_version = WebappWorker::VERSION

					if version.to_s == my_version.to_s
						puts "Already found webapp_worker running, pid is: #{possible_pid}, exiting..."
						@logger.fatal "Found webapp_worker already running with pid: #{possible_pid}, Pid File: #{@pid_file} exiting..."
						exit 1
					else
						puts "Found old version of webapp_worker #{version}, running with pid: #{possible_pid}, asking it to terminate since my version is: #{my_version}"
						@logger.fatal "Found old version of webapp_worker #{version}, running with pid: #{possible_pid}, asking it to terminate since my version is: #{my_version}"

						Process.kill("INT",possible_pid.to_i)

						while WebappWorker::System.process_alive?(possible_pid)
							sleep 120

							begin
                Process.kill("KILL",possible_pid.to_i)
							rescue => error
							end

              self.create_pid
						end
					end
				else
					@logger.warn "Found pid file, but no process running"
					self.create_pid
				end
			else
				@logger.info "Did not find a pid file"
				self.create_pid
			end

			@logger.info "Starting Webapp Worker"
		end

		def start_listening
			begin
				@logger.info "Starting to listen on IPC: #{@ipc_file}"
				DRb.start_service("drbunix:#{@ipc_file}", WebappWorker::VERSION)
				@logger.info "Now listenting on IPC: #{@ipc_file}"
			rescue => error
				@logger.fatal "Error at IPC Start Listenting: #{error}"
			end
		end

		def check_process_version
			@logger.info "Asking the processes version from IPC: #{@ipc_file}"

			DRb.start_service
			version = DRbObject.new_with("drbunix:#{@ipc_file}", nil)

			@logger.info "The process' version is: #{version}"
			return version
		end

		def graceful_termination(threads,command_processes)
			begin
				puts
				puts "Graceful Termination started, waiting 60 seconds before KILL signal send"
				@logger.info "Graceful Termination started, waiting 60 seconds before KILL signal send"

				Timeout::timeout(60) do
					command_processes.each do |pid,command|
						@logger.debug "Sending INT Signal to #{command} Process with PID: #{pid}"

						if WebappWorker::System.process_alive?(pid)
							Process.kill("INT",pid.to_i)
						end
					end

					threads.each do |thread,command|
						thread.join
					end
				end
			rescue Timeout::Error
				puts "Graceful Termination bypassed, killing processes and threads"
				@logger.info "Graceful Termination bypassed, killing processes and threads"

				command_processes.each do |pid,command|
					@logger.debug "Killing #{command} Process with PID: #{pid}"

          if WebappWorker::System.process_alive?(pid)
            Process.kill("KILL",pid.to_i)
          end
				end

				threads.each do |thread,command|
					@logger.debug "Killing Command Thread: #{command}"
					Thread.kill(thread)
				end
			end

			puts "Stopping Webapp Worker"
			@logger.info "Stopping Webapp Worker"

      self.delete_files
			exit 0
		end
	end
end