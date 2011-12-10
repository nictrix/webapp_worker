require 'yaml'

#need to implement a range for each instance variable
#
#class Module
#  def minute_range( key, range=0..59 )
#		define_method(:"#{key}=") do |value|
#			if range.include?( value )
#				self.instance_variable_set("@#{key}", value)
#				self.class.send(:define_method, key, proc{self.instance_variable_get("@#{key}")})
#				self.class.send(:define_method, "#{key}=", proc{|x| self.instance_variable_set("@#{key}", x)})
#			else
#				raise "Minute Out of Range (0..59)"
#			end
#		end
#  end
#end

module WebappWorker
	class Job
		attr_accessor :command, :minute, :hour, :day, :month, :weekday

		DIVISION = /\d+-\d+[\/]\d+/
		DIGIT = /^\d+$/

		def initialize(user_supplied_hash={})
			standard_hash = { command:"", minute:"*", hour:"*", day:"*", month:"*", weekday:"*" }

			user_supplied_hash = standard_hash.merge(user_supplied_hash)

			user_supplied_hash.each do |key,value|
				self.instance_variable_set("@#{key}", value)
				self.class.send(:define_method, key, proc{self.instance_variable_get("@#{key}")})
				self.class.send(:define_method, "#{key}=", proc{|x| self.instance_variable_set("@#{key}", x)})
			end

			self.parse_datetime
		end

		def self.new_from_yaml(yaml)
			job = self.new(YAML.load(yaml))
		end

		def current_time
			return "#{Time.now.strftime("%w %m-%d %H:%M")}"
		end

		def make_string(n)
			test_n = n.to_s.length

			if test_n < 2 && test_n > 0
				return "0#{n}"
			else
				return n.to_s
			end
		end

		def fix_every(value)
			divider = /\d+$/
			range = /^\d+-\d+/
			first_range = /^\d+/
			second_range = /\d+$/

			every = value.match(divider).to_s.to_i
			number_range = value.match(range).to_s
			first = number_range.match(first_range).to_s.to_i
			second = number_range.match(second_range).to_s.to_i

			range = []
			until first >= second do
				first = first + every
				break if first > second
				range << self.make_string(first)
			end

			return range
		end

		def parse_datetime
			self.fix_minute
			self.fix_hour
			self.fix_day
			self.fix_month
			self.fix_weekday
		end

		def fix_minute
			case @minute.to_s
			when "*", nil, ""
				@minute = []
				(0..59).each do |m|
					@minute << self.make_string(m)
				end
			when DIVISION
				@minute = self.fix_every(@minute)
			when DIGIT
				@minute = [self.make_string(@minute)]
			end
		end

		def fix_hour
			case @hour.to_s
			when "*", nil, ""
				@hour = []
				(0..23).each do |h|
					@hour << self.make_string(h)
				end
			when DIVISION
				@hour = self.fix_every(@hour)
			when DIGIT
				@hour = [self.make_string(@hour)]
			end
		end

		def fix_day
			case @day.to_s
			when "*", nil, ""
				@day = []
				(1..31).each do |d|
					@day << self.make_string(d)
				end
			when DIVISION
				@day = self.fix_every(@day)
			when DIGIT
				@day = [self.make_string(@day)]
			end
		end

		def fix_month
			case @month.to_s
			when "*", nil, ""
				@month = []
				(1..12).each do |m|
					@month << self.make_string(m)
				end
			when DIVISION
				@month = self.fix_every(@month)
			when DIGIT
				@month = [self.make_string(@month)]
			end
		end

		def fix_weekday
			case @weekday.to_s
			when "*", nil, ""
				@weekday = []
				(0..6).each do |w|
					@weekday << w.to_s
				end
			when DIVISION
				@weekday = self.fix_every(@weekday)
			when DIGIT
				@weekday = [@weekday.to_s]
			end
		end

		def next_run?
			self.next_runs?(1)
		end

		def next_runs?(til)
			self.parse_datetime

			possible_times = []
			next_runs = []

			now = Time.now
			weekday_now = now.strftime("%w")
			year_now = now.strftime("%Y")
			month_now = now.strftime("%m")
			day_now = now.strftime("%d")
			hour_now = now.strftime("%H")
			minute_now = now.strftime("%M")

			

			@month.each do |month|
				@day.each do |day|
					@weekday.each do |weekday|
						@hour.each do |hour|
							@minute.each do |minute|
								begin
									possible_times << (DateTime.strptime("#{weekday} #{year_now}-#{month}-#{day} #{hour}:#{minute}","%w %Y-%m-%d %H:%M")).to_time
								rescue ArgumentError
									next
								end
							end
						end
					end
				end
			end

			counter = 0
			possible_times.uniq.sort.each do |time|
				if time >= now
					counter = counter + 1
					break if counter > til

					next_runs << time
				end
			end

			return next_runs
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
