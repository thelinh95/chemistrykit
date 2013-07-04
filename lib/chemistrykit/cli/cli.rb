# Encoding: utf-8

require 'thor'
require 'rspec'
require 'ci/reporter/rake/rspec_loader'
require 'chemistrykit/cli/new'
require 'chemistrykit/cli/formula'
require 'chemistrykit/cli/beaker'
require 'chemistrykit/cli/helpers/formula_loader'
require 'chemistrykit/catalyst'
require 'chemistrykit/formula/base'
require 'selenium-connect'
require 'chemistrykit/configuration'

module ChemistryKit
  module CLI

    # Registers the formula and beaker commands
    class Generate < Thor
      register(ChemistryKit::CLI::FormulaGenerator, 'formula', 'formula [NAME]', 'generates a page object')
      register(ChemistryKit::CLI::BeakerGenerator, 'beaker', 'beaker [NAME]', 'generates a beaker')
    end

    # Main Chemistry Kit CLI Class
    class CKitCLI < Thor

      register(ChemistryKit::CLI::New, 'new', 'new [NAME]', 'Creates a new ChemistryKit project')
      check_unknown_options!
      default_task :help

      desc 'generate SUBCOMMAND', 'generate <formula> or <beaker> [NAME]'
      subcommand 'generate', Generate

      desc 'brew', 'Run ChemistryKit'
      method_option :params, type: :hash
      method_option :tag, default: ['depth:shallow'], type: :array
      method_option :config, default: 'config.yaml', aliases: '-c', desc: 'Supply alternative config file.'
      # TODO there should be a facility to simply pass a path to this command
      method_option :beaker, type: :string
      method_option :beakers, type: :array
      method_option :parallel, default: false
      method_option :processes, default: '5'

      def brew
        config = load_config options['config']
        # require 'chemistrykit/shared_context'
        pass_params if options['params']
        turn_stdout_stderr_on_off
        set_logs_dir
        load_page_objects
        setup_tags
        rspec_config(config)

        if options['beaker']
          run_rspec([options['beaker']])
        elsif options['beakers']
          run_rspec([options['beakers']])
        elsif options['parallel']
          run_in_parallel
        else
          ckit_lab_dir = Dir.glob(File.join(Dir.getwd))
          run_rspec ckit_lab_dir
        end
      end

      protected

      def pass_params
        options['params'].each_pair do |key, value|
          ENV[key] = value
        end
      end

      def load_page_objects
        loader = ChemistryKit::CLI::Helpers::FormulaLoader.new
        loader.get_formulas(File.join(Dir.getwd, 'formulas')).each { |file| require file }
      end

      def set_logs_dir
        ENV['CI_REPORTS'] = File.join(Dir.getwd, 'evidence')
      end

      def turn_stdout_stderr_on_off
        ENV['CI_CAPTURE'] = 'on'
      end

      def load_config(file_name)
        config_file = File.join(Dir.getwd, file_name)
        ChemistryKit::Configuration.initialize_with_yaml config_file
      end

      def setup_tags
        @tags = {}
        options['tag'].each do |tag|
          filter_type = tag.start_with?('~') ? :exclusion_filter : :filter

          name, value = tag.gsub(/^(~@|~|@)/, '').split(':')
          name = name.to_sym

          value = true if value.nil?

          @tags[filter_type] ||= {}
          @tags[filter_type][name] = value
        end
      end

      def rspec_config(config) # Some of these bits work and others don't
        SeleniumConnect.configure do |c|
          c.populate_with_hash config.selenium_connect
        end
        RSpec.configure do |c|
          c.treat_symbols_as_metadata_keys_with_true_values = true
          c.filter_run @tags[:filter] unless @tags[:filter].nil?
          c.filter_run_excluding @tags[:exclusion_filter] unless @tags[:exclusion_filter].nil?
          c.before(:each) do
            @driver = SeleniumConnect.start
            @config = config
          end
          c.after(:each) do
            @driver.quit
          end
          c.after(:all) do
            SeleniumConnect.finish
          end
          c.order = 'random'
          c.default_path = 'beakers'
          c.pattern = '**/*_beaker.rb'
        end
      end

      def run_in_parallel
        beakers = Dir.glob('beakers/*')
        puts beakers.inspect
        require 'parallel_tests'
        require 'chemistrykit/parallel_tests_mods'
        ParallelTests::CLI.new.run(%w(--type rspec) + ['-n', options['processes']] + %w(-o --beakers=) + beakers)
      end

      def run_rspec(beakers)
        RSpec::Core::Runner.run(beakers)
      end

    end # CkitCLI
  end # CLI
end # ChemistryKit
