## Information

Provides a way to have workers on your webapp servers, espeically useful for webapps that tend to scale up and down with X amount of servers in the load balancer.  Also good way to not use another dependent resource like a job scheduler/queue.  Keeps your application all packaged up nicely, no cron jobs to set, nothing else to think about setting up and nothing else to maintain.

## Installation

`gem install webapp_worker`

or use it in your Gemfile

`gem 'webapp_worker'`

## Quick Test

``

## Using in your webapp



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