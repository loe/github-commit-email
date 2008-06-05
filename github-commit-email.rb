# Author:: Adam Jacob (<adam@hjksolutions.com>)
# Additions:: W. Andrew Loe III (loe@onehub.com)
# Copyright:: Copyright (c) 2008 HJK Solutions, LLC
# License:: GNU General Public License version 2 or later
# 
# This program and entire repository is free software; you can
# redistribute it and/or modify it under the terms of the GNU 
# General Public License as published by the Free Software 
# Foundation; either version 2 of the License, or any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#

require 'tempfile'
require 'rubygems'
require 'json'
require 'merb-core'
require 'merb-mailer'

Merb::Config.use { |c|
  c[:framework]           = {},
  c[:session_store]       = 'none',
  c[:exception_details]   = true,
  c[:mailto] = "<noreply@example.com>",
  c[:mailfrom] = "<noreply@example.com>"
}

Merb::Mailer.config = {
   :host   => 'localhost',
   :port   => '25',
   :domain => "commitbot" # the HELO domain provided by the client to the server
}

Merb::Router.prepare do |r|
  r.resources :commit
  r.match('/').to(:controller => 'commit', :action =>'index')
end

class Commit < Merb::Controller
  
  def index
    results =  "I accept github post-commits"
    results << " and relay them.  POST to /commit"
    results
  end
  
  def create
    ch = JSON.parse(params[:payload])

    body = <<-EOH
Commits to #{ch['repository']['name']} (#{ch['repository']['url']})
Ref: #{ch['ref']} 

EOH
    ch['commits'].each do |gitsha, commit|
      body << <<-EOH
#{gitsha} by #{commit['author']['name']} (#{commit['author']['email']}) @ #{commit['timestamp']}
#{commit['url']}

#{commit['message']}

EOH
    end

    body << "git diff #{ch['before']} #{ch['after']}\n\n"

    # Clone the repository if it doesn't exist.
    if !File.exist?("/tmp/#{ch['repository']['name']}")
      system "cd /tmp && git clone git@github.com:#{ch['repository']['owner']}/#{ch['repository']['name']}.git"
    end

    # Pull the repo.
    system "cd /tmp/#{ch['repository']['name']} && git-pull"

    # Pipe the diff to a text file and read it back.
    diff = Tempfile.new('diff')
    begin
      diff.close
      system("cd /tmp/#{ch['repository']['name']} && git diff #{ch['before']} #{ch['after']} > #{diff.path}")
      result = File.read(diff.path)
    ensure
      diff.unlink
    end

    body << result

    # Send the email.
    m = Merb::Mailer.new(
    :to => Merb::Config[:mailto],
    :from => Merb::Config[:mailfrom],
    :subject => "GitHub notice for #{ch['repository']['name']}",
    :text => body
    )
    m.deliver!
    Merb.logger.info("Commit Sent")
  end
end