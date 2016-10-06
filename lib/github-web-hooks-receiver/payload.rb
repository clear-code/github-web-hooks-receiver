# Copyright (C) 2010-2016  Kouhei Sutou <kou@clear-code.com>
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

module GitHubWebHooksReceiver
  class Payload
    def initialize(data, metadata={})
      @data = data
      @metadata = metadata
    end

    def [](key)
      key.split(".").inject(@data) do |current_data, current_key|
        if current_data
          current_data[current_key]
        else
          nil
        end
      end
    end

    def repository_url
      if gitlab_wiki?
        self["wiki.git_ssh_url"]
      elsif gitlab?
        self["repository.url"]
      elsif github_gollum?
        self["repository.clone_url"].gsub(/(\.git)\z/, ".wiki\\1")
      else
        self["repository.clone_url"] || "#{self['repository.url']}.git"
      end
    end

    def gitlab?
      self["user_name"] or self["object_kind"]
    end

    def gitlab_wiki?
      event_name == "Wiki Page Hook"
    end

    def github_gollum?
      event_name == "gollum"
    end

    def event_name
      if gitlab?
        @metadata["x-gitlab-event"]
      else
        @metadata["x-github-event"]
      end
    end
  end
end
