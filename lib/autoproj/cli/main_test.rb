module Autoproj
    module CLI
        class MainTest < Thor
            namespace 'test'

            default_command 'exec'

            no_commands do
                def report(report_options = Hash.new)
                    Autoproj.report(Hash[silent: !options[:debug], debug: options[:debug]].merge(report_options)) do
                        yield
                    end
                end
            end
            
            desc 'enable [PACKAGES]', 'enable tests for the given packages (or for all packages if none are given)'
            option :deps, type: :boolean, default: false,
                desc: 'controls whether the dependencies of the packages given on the command line should be enabled as well (the default is not)'
            def enable(*packages)
                require 'autoproj/cli/test'
                report(silent: true) do
                    cli = Test.new
                    args = cli.validate_options(packages, options)
                    cli.enable(*args)
                end
            end

            desc 'disable [PACKAGES]', 'disable tests for the given packages (or for all packages if none are given)'
            option :deps, type: :boolean, default: false,
                desc: 'controls whether the dependencies of the packages given on the command line should be disabled as well (the default is not)'
            def disable(*packages)
                require 'autoproj/cli/test'
                report(silent: true) do
                    cli = Test.new
                    args = cli.validate_options(packages, options)
                    cli.disable(*args)
                end
            end

            desc 'list [PACKAGES]', 'show test enable/disable status for the given packages (or all packages if none are given)'
            option :deps, type: :boolean, default: true,
                desc: 'controls whether the dependencies of the packages given on the command line should be disabled as well (the default is not)'
            def list(*packages)
                require 'autoproj/cli/test'
                report(silent: true) do
                    cli = Test.new
                    args = cli.validate_options(packages, options)
                    cli.list(*args)
                end
            end

            desc 'exec [PACKAGES]', 'execute the tests for the given packages, or all if no packages are given on the command line'
            option :keep_going, aliases: :k, type: :boolean,
                banner: '',
                desc: 'do not stop on build or checkout errors'
            option :deps, type: :boolean, default: false,
                desc: 'controls whether to execute the tests of the dependencies of the packages given on the command line (the default is not)'
            option :fail, type: :boolean, default: true,
                desc: 'return with a nonzero exit code if the test does not pass'
            option :coverage, type: :boolean, default: false,
                desc: 'whether code coverage should be generated if possible'
            def exec(*packages)
                require 'autoproj/cli/test'
                report do
                    cli = Test.new
                    Autobuild.pass_test_errors = options[:fail]
                    Autobuild.ignore_errors = options[:keep_going]
                    Autobuild::TestUtility.coverage_enabled = options[:coverage]
                    args = cli.validate_options(packages, deps: options[:deps])
                    cli.run(*args)
                end
            end
        end
    end
end


