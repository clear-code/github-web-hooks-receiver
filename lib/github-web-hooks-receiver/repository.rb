# Copyright (C) 2010-2018  Kouhei Sutou <kou@clear-code.com>
# Copyright (C) 2015  Kenji Okimoto <okimoto@clear-code.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require "stringio"

module GitHubWebHooksReceiver
  class Repository
    include PathResolver

    class Error < StandardError
    end

    def initialize(domain, owner_name, name, payload, options)
      @domain = domain
      @owner_name = owner_name
      @name = name
      @payload = payload
      @options = options
      @to = @options[:to]
      @max_n_retries = (@options[:n_retries] || 3).to_i
      @use_ssh = @options[:use_ssh]
      raise Error.new("mail receive address is missing: <#{@name}>") if @to.nil?
    end

    def enabled?
      enabled = @options[:enabled]
      enabled = true if enabled.nil?
      enabled
    end

    def process(before, after, reference)
      FileUtils.mkdir_p(File.dirname(mirror_path))
      n_retries = 0
      lock("#{mirror_path}.lock") do
        begin
          if File.exist?(mirror_path)
            git("--git-dir", mirror_path, "fetch", "--quiet", "--prune")
          else
            if @use_ssh
              clone_url = @payload.ssh_clone_url
            else
              clone_url = @payload.http_clone_url
            end
            git("clone", "--quiet",
                "--mirror", clone_url,
                mirror_path)
          end
        rescue Error
          n_retries += 1
          retry if n_retries <= @max_n_retries
          raise
        end
      end
      send_commit_email(before, after, reference)
    end

    def lock(path)
      File.open(path, "w") do |file|
        file.flock(File::LOCK_EX)
        yield
      end
    end

    def send_commit_email(before, after, reference)
      options = [
        "--repository", mirror_path,
        "--max-size", "1M"
      ]
      if @payload.gitlab?
        if @payload.gitlab_wiki?
          add_option(options, "--repository-browser", "gitlab-wiki")
          gitlab_project_uri = @payload["project"]["homepage"]
        else
          add_option(options, "--repository-browser", "gitlab")
          gitlab_project_uri = @payload["repository"]["homepage"]
        end
        add_option(options, "--gitlab-project-uri", gitlab_project_uri)
      else
        if @payload.github_gollum?
          add_option(options, "--repository-browser", "github-wiki")
        else
          add_option(options, "--repository-browser", "github")
        end
        add_option(options, "--github-user", @owner_name)
        add_option(options, "--github-repository", @name)
        name = "#{@owner_name}/#{@name}"
        name << ".wiki" if @payload.github_gollum?
        add_option(options, "--name", name)
      end
      add_option(options, "--from", from)
      add_option(options, "--from-domain", from_domain)
      add_option(options, "--sender", sender)
      add_option(options, "--sleep-per-mail", sleep_per_mail)
      options << "--send-per-to" if send_per_to?
      options << "--add-html" if add_html?
      error_to.each do |_error_to|
        options.concat(["--error-to", _error_to])
      end
      if @to.is_a?(Array)
        options.concat(@to)
      else
        options << @to
      end
      command_line = [ruby, git_commit_mailer, *options].collect do |component|
        Shellwords.escape(component)
      end.join(" ")
      change = "#{before} #{after} #{reference}"
      status = nil
      output = capture_output do
        IO.popen(command_line, "r+") do |io|
          io.puts(change)
          io.close_wirte
          print(io.read)
        end
        status = $?
      end
      unless status.success?
        raise Error.new("failed to run git-commit-mailer: " +
                        "<#{command_line}>:<#{change}>:<#{output}>")
      end
    end

    private
    def git(*arguments)
      arguments = arguments.collect {|argument| argument.to_s}
      command_line = [git_command, *arguments]
      unless system(*command_line)
        raise Error.new("failed to run command: <#{command_line.join(' ')}>")
      end
    end

    def git_command
      @git ||= @options[:git] || "git"
    end

    def mirrors_directory
      @mirrors_directory ||=
        @options[:mirrors_directory] ||
        path("mirrors")
    end

    def mirror_path
      components = [mirrors_directory, @domain, @owner_name]
      if @payload.github_gollum? or @payload.gitlab_wiki?
        components << "#{@name}.wiki"
      else
        components << @name
      end
      File.join(*components)
    end

    def ruby
      @ruby ||= @options[:ruby] || RbConfig.ruby
    end

    def commit_email
      @commit_email ||=
        @options[:commit_email] ||
        path("..", "commit-email.rb")
    end

    def git_commit_mailer
      @git_commit_mailer ||= @options[:git_commit_mailer] || commit_email
    end

    def from
      @from ||= @options[:from]
    end

    def from_domain
      @from_domain ||= @options[:from_domain]
    end

    def sender
      @sender ||= @options[:sender]
    end

    def sleep_per_mail
      @sleep_per_mail ||= @options[:sleep_per_mail]
    end

    def error_to
      @error_to ||= force_array(@options[:error_to])
    end

    def send_per_to?
      @options[:send_per_to]
    end

    def add_html?
      @options[:add_html]
    end

    def force_array(value)
      if value.is_a?(Array)
        value
      elsif value.nil?
        []
      else
        [value]
      end
    end

    def add_option(options, name, value)
      return if value.nil?
      value = value.to_s
      return if value.empty?
      options.concat([name, value])
    end

    def capture_output
      output = StringIO.new
      stdout = $stdout
      stderr = $stderr
      begin
        $stdout = output
        $stderr = output
        yield
      ensure
        $stdout = stdout
        $stderr = stderr
      end
      output.string
    end
  end
end
