require 'etc'

module WebappWorker
	class System

		attr_accessor :user, :tmp_dir, :pid_file, :ipc_file, :logger

		def initialize(user_supplied_hash={})
			standard_hash = { user:"nobody", tmp_dir:"/tmp/webapp_worker/application.log", pid_file:"waw.pid", ipc_file:"drbunix:/tmp/webapp_worker/waw", logger:"" }

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
      self.create_logger
      self.start_listening
      self.check_for_process
      self.drop_priviledges
    end

    def drop_priviledges
      begin
        uid = Etc.getpwnam(@user).uid
        Process::Sys.setuid(uid)
      rescue Errno::EPERM
        true
      else
        false
      end
    end

		def check_for_directory
			@tmp_dir = "/tmp/webapp_worker"

			if Dir.exists?(@tmp_dir)
			else
				Dir.mkdir(@tmp_dir, 0700)
				File.chown(@user,@user,@tmp_dir)
			end
		end

    def create_logger
      @logger = Logger.new(@tmp_dir, 5, 5242880)

      if debug
        @logger.level = Logger::DEBUG
      elsif verbose
        @logger.level = Logger::INFO
      else
        @logger.level = Logger::WARN
      end
    end

		def create_pid
			@logger.info "Creating Pid File at #{@pid_file}"
			File.open(@pid_file, 'w') { |f| f.write(Process.pid) }
			@logger.info "Pid File created: #{Process.pid} at #{@pid_file}"
		end

		def check_for_process
			if File.exists?(@pid_file)
				possible_pid = ""
				pid_file = File.open(@pid_file, 'r').each { |f| possible_pid+= f }
				pid_file.close

				if WebappWorker::System.process_alive?(possible_pid)
					if self.check_process_version == WebappWorker::VERSION
						puts "Already found webapp_worker running, pid is: #{possible_pid}, exiting..."
						@logger.fatal "Found webapp_worker already running with pid: #{possible_pid}, Pid File: #{@pid_file} exiting..."
						exit 1
					else
						puts "Found old version of webapp_worker running with pid: #{possible_pid}, asking it to terminate"
						@logger.fatal "Found old version of webapp_worker running with pid: #{possible_pid}, asking it to terminate"

						Process.kill("INT",possible_pid.to_i)

						while WebappWorker::System.process_alive?(possible_pid)
							sleep 120
							Process.kill("KILL",possible_pid.to_i)
						end
					end
				else
					@logger.warn "Found pid file, but no process running, recreating pid file with my pid: #{Process.pid}"
					File.delete(@pid_file)
					self.create_pid
				end
			else
				self.create_pid
			end

			@logger.info "Starting Webapp Worker"
		end

		def start_listening
			DRb.start_service(@ipc_file, WebappWorker::VERSION)
		end

		def check_process_version
			DRbObject.new_with(@ipc_file, version)

			return version.to_i
		end
	end
end