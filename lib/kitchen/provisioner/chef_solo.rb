# -*- encoding: utf-8 -*-
#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2013, Fletcher Nichol
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "kitchen/provisioner/chef_base"

module Kitchen
  module Provisioner
    # Chef Solo provisioner.
    #
    # @author Fletcher Nichol <fnichol@nichol.ca>
    class ChefSolo < ChefBase
      kitchen_provisioner_api_version 2

      plugin_version Kitchen::VERSION

      default_config :solo_rb, {}

      default_config :chef_solo_path do |provisioner|
        provisioner
          .remote_path_join(%W{#{provisioner[:chef_omnibus_root]} bin chef-solo})
          .tap { |path| path.concat(".bat") if provisioner.windows_os? }
      end

      # (see Base#config_filename)
      def config_filename
        "solo.rb"
      end

      # (see Base#create_sandbox)
      def create_sandbox
        super
        prepare_config_rb
        prepare_script
      end

      def modern?
        version = config[:require_chef_omnibus]

        case version
        when nil, false, true, 11, "11", "latest"
          true
        else
          if Gem::Version.correct?(version)
            Gem::Version.new(version) >= Gem::Version.new("11.0") ? true : false
          else
            true
          end
        end
      end

      # (see Base#run_command)
      def run_command
        ## begin of bootstrap
        # added shell provision to run before converge
        script = remote_path_join(
         config[:root_path], File.basename(config[:script])
        )

        code = powershell_shell? ? %{& "#{script}"} : sudo(script)
        prefix_command(wrap_shell_code(code))

	## end of bootstrap

        config[:log_level] = "info" if !modern? && config[:log_level] = "auto"
        cmd = sudo(config[:chef_solo_path]).dup
                                           .tap { |str| str.insert(0, "& ") if powershell_shell? }

        chef_cmd(cmd)
      end

      private


      def prepare_script
        info("Preparing script")

        if config[:script]
          debug("Using script from #{config[:script]}")
          FileUtils.cp_r(config[:script], sandbox_path)
        else
          prepare_stubbed_script
        end

        FileUtils.chmod(0755,
                        File.join(sandbox_path, File.basename(config[:script])))
      end

      # Create a minimal, no-op script in the sandbox path.
      #
      # @api private
      def prepare_stubbed_script
        base = powershell_shell? ? "bootstrap.ps1" : "bootstrap.sh"
        config[:script] = File.join(sandbox_path, base)
        info("#{File.basename(config[:script])} not found " \
          "so Kitchen will run a stubbed script. Is this intended?")
        File.open(config[:script], "wb") do |file|
          if powershell_shell?
            file.write(%{Write-Host "NO BOOTSTRAP SCRIPT PRESENT`n"\n})
          else
            file.write(%{#!/bin/sh\necho "NO BOOTSTRAP SCRIPT PRESENT"\n})
          end
        end
      end

      # Returns an Array of command line arguments for the chef client.
      #
      # @return [Array<String>] an array of command line arguments
      # @api private
      def chef_args(solo_rb_filename)
        args = [
          "--config #{remote_path_join(config[:root_path], solo_rb_filename)}",
          "--log_level #{config[:log_level]}",
          "--no-color",
          "--json-attributes #{remote_path_join(config[:root_path], 'dna.json')}",
        ]
        args << " --force-formatter" if modern?
        args << "--logfile #{config[:log_file]}" if config[:log_file]
        args << "--profile-ruby" if config[:profile_ruby]
        args << "--legacy-mode" if config[:legacy_mode]

        args
      end
    end
  end
end
