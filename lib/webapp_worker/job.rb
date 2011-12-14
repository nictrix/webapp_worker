require 'yaml'
require 'time'

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

			user_supplied_hash = {} unless user_supplied_hash
			user_supplied_hash = standard_hash.merge(user_supplied_hash)

			user_supplied_hash.each do |key,value|
				self.instance_variable_set("@#{key}", value)
				self.class.send(:define_method, key, proc{self.instance_variable_get("@#{key}")})
				self.class.send(:define_method, "#{key}=", proc{|x| self.instance_variable_set("@#{key}", x)})
			end

			self.parse_datetime
		end

		def self.new_from_yaml(yaml,environment)
			job = self.new((YAML.load_file(yaml))[environment])
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

		def next_times(numbers,amount,time)
			future = {}

			numbers.each do |number|
				calculated = number.to_i - time
				calculated = (calculated + amount) unless calculated >= 0
				future.store(number,calculated)
			end

			sub = {}
			(future.sort_by { |key,value| value }).collect { |key,value| sub.store(key,value) }
			fn = sub.collect { |key,value| key }

			return fn
		end

		def next_run?
			self.next_runs?(1)
		end

		def next_runs?(til)
			self.parse_datetime

			next_runs = []

			now = Time.now
			@weekday = self.next_times(@weekday,6,now.strftime("%w").to_i)
			@year = now.strftime("%Y")
			@month = self.next_times(@month,12,now.strftime("%m").to_i)
			@day = self.next_times(@day,31,now.strftime("%d").to_i)
			@hour = self.next_times(@hour,23,now.strftime("%H").to_i)
			@minute = self.next_times(@minute,60,now.strftime("%M").to_i)

			counter = 0
			catch :done do
				@month.each do |month|
					@day.each do |day|
						@weekday.each do |weekday|
							@hour.each do |hour|
								@minute.each do |minute|
									begin
										next_time = (DateTime.strptime("#{weekday} #{@year}-#{month}-#{day} #{hour}:#{minute}","%w %Y-%m-%d %H:%M")).to_time + 25200

										next unless next_time >= now
										next_runs << next_time
										counter = counter + 1
									rescue ArgumentError
										next
									end

									throw :done, next_runs if counter >= til
								end
							end
						end
					end
				end

				return next_runs
			end
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
