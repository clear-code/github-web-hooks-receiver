# -*- coding: utf-8 -*-
#
# Copyright (C) 2010-2013  Kouhei Sutou <kou@clear-code.com>
# Copyright (C) 2015       Kenji Okimoto <okimoto@clear-code.com>
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
  module PathResolver
    def base_dir
      @base_dir ||=
        @options[:base_dir] ||
        File.expand_path(File.join(File.dirname(__FILE__), ".."))
    end

    def path(*paths)
      File.expand_path(File.join(base_dir, *paths))
    end
  end
end
