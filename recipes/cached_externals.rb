# ---------------------------------------------------------------------------
# This is a recipe definition file for Capistrano. The tasks are documented
# below.
# ---------------------------------------------------------------------------
# This file is distributed under the terms of the MIT license by 37signals,
# LLC, and is copyright (c) 2008 by the same. See the LICENSE file distributed
# with this file for the complete text of the license.
# ---------------------------------------------------------------------------

# The :external_modules variable is used internally to load and contain the
# contents of the config/externals.yml file. Although you _could_ set the
# variable yourself (to bypas the need for a config/externals.yml file, for
# instance), you'll rarely (if ever) want to.
set(:external_modules) do
  require 'yaml'

  modules = YAML.load_file("config/externals.yml") rescue {}
  modules.each do |path, options|
    strings = options.select { |k, v| String === k }
    raise ArgumentError, "the externals.yml file must use symbols for the option keys (found #{strings.inspect} under #{path})" if strings.any?
  end
end

desc "Indicate that externals should be applied locally. See externals:setup."
task :local do
  set :stage, :local
end

namespace :externals do
  desc <<-DESC
    Set up all defined external modules. This will check to see if any of the
    modules need to be checked out (be they new or just updated), and will then
    create symlinks to them. If running in 'local' mode (see the :local task)
    then these will be created in a "../externals/" directory relative
    to the project root. Otherwise, these will be created on the remote
    machines under [shared_path]/externals.
  DESC
  task :setup, :except => { :no_release => true } do
    require 'capistrano/recipes/deploy/scm'

    external_modules.each do |path, options|
      puts "configuring & linking #{path}"
      scm = Capistrano::Deploy::SCM.new(options[:type], options)

      if exists?(:stage) && stage == :local
        FileUtils.rm_rf(path)
        destination = options[:working_dir] || File.expand_path(File.join("../externals/", path.split(File::SEPARATOR).last))
        if !File.exists?(destination)
          unless system(scm.checkout("HEAD", destination))
            FileUtils.rm_rf(destination) if File.exists?(destination)
            raise "Error cloning #{repository} to #{destination}"
          end
        end
        FileUtils.ln_s(destination, path)
      else
        revision = scm.query_revision(options[:revision]) { |cmd| `#{cmd}` }
        shared = File.join(shared_path, "externals", path)
        destination = File.join(shared, revision)
        run "rm -rf #{latest_release}/#{path} && mkdir -p #{shared} && if [ ! -d #{destination} ]; then (#{scm.checkout(revision, destination)}) || rm -rf #{destination}; fi && ln -nsf #{destination} #{latest_release}/#{path}"
      end
    end
  end
  
  desc <<-DESC
    Update defined external modules (same as setup). If running in 'local' mode (see the :local task), 
    this will synchronize local modules to the HEAD of SCM configured in externals.yml
  DESC
  task :update, :except => { :no_release => true } do
    if exists?(:stage) && stage == :local
      external_modules.each do |path, options|
        puts "Updating #{path}"
        scm = Capistrano::Deploy::SCM.new(options[:type], options)
        
        destination = options[:working_dir] || File.expand_path(File.join("../externals/", path.split(File::SEPARATOR).last))
        raise "#{destination} is missing. Please run 'cap local externals:setup'" if !File.exists?(destination)
        unless system(scm.sync("HEAD", destination))
          raise "Error synchronizing #{destination} with SCM"
        end
      end
    else
      setup
    end
  end
  
end


# Need to do this before finalize_update, instead of after update_code,
# because finalize_update tries to do a touch of all assets, and some
# assets might be symlinks to files in plugins that have been externalized.
# Updating those externals after finalize_update means that the plugins
# haven't been set up yet when the touch occurs, causing the touch to
# fail and leaving some assets temporally out of sync, potentially, with
# the other servers.
before "deploy:finalize_update", "externals:setup"
