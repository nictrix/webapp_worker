## Information

Provides a way to have workers on your webapp servers, especially useful for webapps that tend to scale up and down with X amount of servers in the load balancer.  Also good way to not use another dependent resource like a job scheduler/queue.  Keeps your application all packaged up nicely, no cron jobs to set, nothing else to think about setting up and nothing else to maintain.

## Installation

`gem install webapp_worker`

or use it in your Gemfile

`gem 'webapp_worker'`

## Quick Test

	waw -e development -f jobs.yml (parses data)
	waw -e development -f jobs.yml  -j (parses and shows jobs)
	waw -e development -f jobs.yml  -n 4 (parses and shows the next N run times, by job)
	waw -e development -f jobs.yml -r (parses and starts to run)
	waw -e development -f jobs.yml -d (parses and turns on debugging)
	waw -e development -f jobs.yml -v (parses and turns on verbose logging)

## Using in your webapp

Create a jobs yaml file.

	---
	local:
		mailto: user@nobody.com
		actual_hostname:
			- :command: "rake test"
				:minute: 0
			- :command: "rake test"
				:minute: 45

Load this file somewhere in your web app, like an initializer file.

	jobs = "config/jobs.yml"

	a = WebappWorker::Application.new(environment:"development",mailto:"")
	a.parse_yaml(jobs)
	a.run

You don't have to use a jobs file, you can specify the yaml or hash in the code above like this:

	job = {:command=>"rake job:run", :minute=>"0-59/5", :hour=>"0-4/2", :day=>1, :month=>"0-12/1"}

	a = WebappWorker::Application.new(environment:"development",mailto:"",jobs:[job])
	a.run

## Example Output of waw

See if Webapp Worker can parse the jobs file and show you all the jobs it can run from the file

	$ waw -e local -f config/jobs.yml -j
	Job File: config/jobs.yml

	Host: localhost
	Mailto:
	Environment: development
	Amount of Jobs: 3

	Job: `rake job:run`
	Job: `rake job:run`
	Job: `rake job:run`

See when the jobs are supposed to run next, next two times, next three times, etc...

	$ waw -e local -f config/jobs.yml -n 4
	Job: `rake job:run`
	   Next Run Time(s): [2012-01-03 22:00:00 -0700, 2012-01-03 22:05:00 -0700, 2012-01-03 22:10:00 -0700, 2012-01-03 22:15:00 -0700]
	Job: `rake job:run`
	   Next Run Time(s): [2012-01-03 22:00:00 -0700, 2012-01-03 22:05:00 -0700, 2012-01-03 22:10:00 -0700, 2012-01-03 22:15:00 -0700]

Run the actual jobs from the command line

	$ waw -e local -f config/jobs.yml -r (optional -d and -v for debug and verbose)
	Running Jobs

## Other Options

You may want to know what version of the gem Webapp Worker is using, so just send a USR1 signal to it

	$ kill -s USR1 11682
	Webapp Worker Version: 0.0.4

You may need to turn on debugging for the Webapp Worker while its running, so just send a USR2 signal to it

	$ kill -s USR2 11682
	Changed logger level to Debug

## Roadmap

- Start creating tests
- Use the mailto attribute in application to actually do something
- Start having the webapp worker registering to a central point or do UDP mutlicasting to find each other.
- Once self registering is enabled, webapp_workers need to communicate effectively.
- Once communication is established webapp_workers need to do the scheduling for themselves.
- Do logging for each type of job in a jobs directory under tmp/webapp_worker, allowing for troubleshooting.
- Spit out reports of the different jobs and how fast they run.

## Contributing

- Fork the project and do your work in a topic branch.
- Rebase your branch to make sure everything is up to date.
- Commit your changes and send a pull request.

## Copyright

(The MIT License)

Copyright © 2011 nictrix (Nick Willever)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
