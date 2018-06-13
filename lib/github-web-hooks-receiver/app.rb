# Copyright (C) 2010-2013  Kouhei Sutou <kou@clear-code.com>
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

require "github-web-hooks-receiver/base"
require "github-web-hooks-receiver/path-resolver"
require "github-web-hooks-receiver/payload"
require "github-web-hooks-receiver/repository"

module GitHubWebHooksReceiver
  class App < Base
    include PathResolver

    private

    def process_payload(request, response, raw_payload)
      metadata = {
        "x-github-event" => github_event(request),
        "x-gitlab-event" => gitlab_event(request),
      }
      payload = Payload.new(raw_payload, metadata)
      case payload.event_name
      when "ping"
        # Do nothing
      when "push"
        process_push_payload(request, response, payload)
      when "gollum"
        process_gollum_payload(request, response, payload)
      when "wiki_page"
        process_gitlab_wiki_payload(request, response, payload)
      else
        set_response(response,
                     :bad_request,
                     "Unsupported event: <#{payload.event_name}>")
      end
    end

    def github_event(request)
      request.env["HTTP_X_GITHUB_EVENT"]
    end

    def gitlab_event(request)
      request.env["HTTP_X_GITLAB_EVENT"]
    end

    def process_push_payload(request, response, payload)
      repository = process_payload_repository(request, response, payload)
      return if repository.nil?
      change = process_push_parameters(request, response, payload)
      return if change.nil?
      @job_queue.push do
        repository.process(*change)
      end
    end

    def process_gollum_payload(request, response, payload)
      repository = process_payload_repository(request, response, payload)
      return if repository.nil?
      change = process_gollum_parameters(request, response, payload)
      return if change.nil?
      @job_queue.push do
        repository.process(*change)
      end
    end

    def process_gitlab_wiki_payload(request, response, payload)
      repository = process_gitlab_wiki_repository(request, response, payload)
      return if repository.nil?
      change = process_gitlab_wiki_parameters(request, response, payload)
      return if change.nil?
      @job_queue.push do
        repository.process(*change)
      end
    end

    def process_payload_repository(request, response, payload)
      repository = payload["repository"]
      if repository.nil?
        set_response(response, :bad_request,
                     "repository information is missing")
        return
      end

      unless repository.is_a?(Hash)
        set_response(response, :bad_request,
                     "invalid repository information format: " +
                     "<#{repository.inspect}>")
        return
      end

      repository_uri = repository["url"]
      domain = extract_domain(repository_uri)
      if domain.nil?
        set_response(response, :bad_request,
                     "invalid repository URI: <#{repository.inspect}>")
        return
      end

      repository_name = repository["name"]
      if repository_name.nil?
        set_response(response, :bad_request,
                     "repository name is missing: <#{repository.inspect}>")
        return
      end

      owner_name = extract_owner_name(repository_uri, payload)
      if owner_name.nil?
        set_response(response, :bad_request,
                     "repository owner or owner name is missing: " +
                     "<#{repository.inspect}>")
        return
      end

      options = repository_options(domain, owner_name, repository_name)
      repository = repository_class.new(domain, owner_name, repository_name,
                                        payload, options)
      unless repository.enabled?
        set_response(response, :accepted,
                     "ignore disabled repository: " +
                     "<#{owner_name.inspect}>:<#{repository_name.inspect}>")
        return
      end

      repository
    end

    def process_gitlab_wiki_repository(request, response, payload)
      wiki = payload["wiki"]
      if wiki.nil?
        set_response(response, :bad_request,
                     "Wiki information is missing")
        return
      end

      unless wiki.is_a?(Hash)
        set_response(response, :bad_request,
                     "invalid Wiki information format: " +
                     "<#{wiki.inspect}>")
        return
      end

      repository_uri = wiki["git_ssh_url"]
      domain = extract_domain(repository_uri)
      if domain.nil?
        set_response(response, :bad_request,
                     "invalid repository URI: <#{wiki.inspect}>")
        return
      end

      project = payload["project"]
      if wiki.nil?
        set_response(response, :bad_request,
                     "Project information is missing")
        return
      end

      repository_name = project["name"]
      if repository_name.nil?
        set_response(response, :bad_request,
                     "repository name is missing: <#{project.inspect}>")
        return
      end

      owner_name = extract_owner_name(repository_uri, payload)
      if owner_name.nil?
        set_response(response, :bad_request,
                     "repository owner or owner name is missing: " +
                     "<#{project.inspect}>")
        return
      end

      options = repository_options(domain, owner_name, repository_name)
      repository = repository_class.new(domain, owner_name, repository_name,
                                        payload, options)
      unless repository.enabled?
        set_response(response, :accepted,
                     "ignore disabled repository: " +
                     "<#{owner_name.inspect}>:<#{repository_name.inspect}>")
        return
      end

      repository
    end

    def extract_domain(repository_uri)
      case repository_uri
      when /\Agit@/
        repository_uri[/@(.+):/, 1]
      when /\Ahttps:\/\//
        URI.parse(repository_uri).hostname
      else
        nil
      end
    end

    def extract_owner_name(repository_uri, payload)
      owner_name = nil
      if payload.gitlab?
        case repository_uri
        when /\Agit@/
          owner_name = repository_uri[%r!git@.+:(.+)/.+(?:.git)?!, 1]
        when /\Ahttps:\/\//
          owner_name = URI.parse(repository_uri).path.sub(/\A\//, "")
        else
          return
        end
      else
        owner = payload["repository.owner"]
        return if owner.nil?

        owner_name = owner["name"] || owner["login"]
        return if owner_name.nil?
      end
      owner_name
    end

    def process_push_parameters(request, response, payload)
      before = payload["before"]
      if before.nil?
        set_response(response, :bad_request,
                     "before commit ID is missing")
        return
      end

      after = payload["after"]
      if after.nil?
        set_response(response, :bad_request,
                     "after commit ID is missing")
        return
      end

      reference = payload["ref"]
      if reference.nil?
        set_response(response, :bad_request,
                     "reference is missing")
        return
      end

      [before, after, reference]
    end

    def process_gollum_parameters(request, response, payload)
      pages = payload["pages"]
      if pages.nil?
        set_response(response, :bad_request,
                     "pages are missing")
        return
      end
      if pages.empty?
        set_response(response, :bad_request,
                     "no pages")
        return
      end

      revisions = pages.collect do |page|
        page["sha"]
      end

      if revisions.size == 1
        after = revisions.first
        before = "#{after}^"
      else
        before = revisions.first
        after = revisions.last
      end

      reference = "refs/heads/master"
      [before, after, reference]
    end

    def process_gitlab_wiki_parameters(request, response, payload)
      before = "HEAD~"
      after = "HEAD"
      reference = "refs/heads/master"
      [before, after, reference]
    end

    def set_response(response, status_keyword, message)
      if File.directory?("log")
        begin
          require "pp"
          File.open("log/response.log", "w") do |log|
            PP.pp([status_keyword, message], log)
          end
        rescue SystemCallError
        end
      end
      response.status = status(status_keyword)
      response["Content-Type"] = "text/plain"
      response.write(message)
    end

    def repository_class
      @options[:repository_class] || Repository
    end

    def repository_options(domain, owner_name, repository_name)
      domain_options = (@options[:domains] || {})[domain] || {}
      domain_options = symbolize_options(domain_options)
      domain_owner_options = (domain_options[:owners] || {})[owner_name] || {}
      domain_owner_options = symbolize_options(domain_owner_options)
      domain_repository_options = (domain_owner_options[:repositories] || {})[repository_name] || {}
      domain_repository_options = symbolize_options(domain_repository_options)

      owner_options = (@options[:owners] || {})[owner_name] || {}
      owner_options = symbolize_options(owner_options)
      _repository_options = (owner_options[:repositories] || {})[repository_name] || {}
      _repository_options = symbolize_options(_repository_options)

      options = @options.merge(owner_options)
      options = options.merge(owner_options)
      options = options.merge(_repository_options)

      options = options.merge(domain_options)
      options = options.merge(domain_owner_options)
      options = options.merge(domain_repository_options)
      options
    end
  end
end
