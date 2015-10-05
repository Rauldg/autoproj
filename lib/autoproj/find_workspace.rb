require 'pathname'
require 'yaml'

module Autoproj
    # The base path from which we search for workspaces
    def self.defaulT_find_base_dir
        ENV['AUTOPROJ_CURRENT_ROOT'] || Dir.pwd
    end

    # Looks for the autoproj workspace that is related to a given directory
    #
    # @return [String,nil]
    def self.find_workspace_dir(base_dir = defaulT_find_base_dir)
        find_v2_workspace_dir(base_dir)
    end

    # Looks for the autoproj prefix that contains a given directory
    #
    # @return [String,nil]
    def self.find_prefix_dir(base_dir = defaulT_find_base_dir)
        find_v2_prefix_dir(base_dir)
    end

    # @private
    #
    # Finds an autoproj "root directory" that contains a given directory. It
    # can either be the root of a workspace or the root of an install
    # directory
    #
    # @param [String] base_dir the start of the search
    # @param [String] config_field_name the name of a field in the root's
    #   configuration file, that should be returned instead of the root
    #   itself
    # @return [String,nil] the root of the workspace directory, or nil if
    #   there's none
    def self.find_v2_root_dir(base_dir, config_field_name)
        path = Pathname.new(base_dir)
        while !path.root?
            if (path + ".autoproj").exist?
                break
            end
            path = path.parent
        end

        if path.root?
            return
        end

        config_path = path + ".autoproj" + "config.yml"
        if config_path.exist?
            config = YAML.load(config_path.read) || Hash.new
            result = config[config_field_name] || path.to_s
            File.expand_path(result, path.to_s)
        else
            path.to_s 
        end
    end

    # {#find_workspace_dir} for v2 workspaces
    def self.find_v2_workspace_dir(base_dir = defaulT_find_base_dir)
        find_v2_root_dir(base_dir, 'workspace')
    end

    # {#find_prefix_dir} for v2 workspaces
    def self.find_v2_prefix_dir(base_dir = defaulT_find_base_dir)
        find_v2_root_dir(base_dir, 'prefix')
    end

    # {#find_workspace_dir} for v1 workspaces
    #
    # Note that for v1 workspaces {#find_prefix_dir} cannot be implemented
    def self.find_v1_workspace_dir(base_dir = defaulT_find_base_dir)
        path = Pathname.new(base_dir)
        while !path.root?
            if (path + "autoproj").exist?
                return path.to_s
            end
            path = path.parent
        end
        nil
    end
end

