require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class OSDeps < InspectionTool
            def run(user_selection, update: true, **options)
                initialize_and_load
                _, osdep_packages, resolved_selection, _ =
                    finalize_setup(user_selection)

                shell_helpers = options.fetch(:shell_helpers, ws.config.shell_helpers?)

                ws.install_os_packages(
                    osdep_packages,
                    run_package_managers_without_packages: true,
                    install_only: !update)
                export_env_sh(shell_helpers: shell_helpers)
            end
        end
    end
end

