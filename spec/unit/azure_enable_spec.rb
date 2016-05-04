require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'chef/azure/commands/enable'
require 'ostruct'

describe EnableChef do
  let (:extension_root) { "./" }
  let (:enable_args) { [] }
  let (:instance) { EnableChef.new(extension_root, enable_args) }

  it { expect {instance}.to_not raise_error }

  context "run" do
    context "chef service is enabled" do
      context "chef-client run was successful" do
        it "reports chef service enabled to heartbeat" do
          expect(instance).to receive(:load_env)
          expect(instance).to receive(:report_heart_beat_to_azure).with(AzureHeartBeat::NOTREADY, 0, "Enabling chef-service...")
          expect(instance).to receive(:enable_chef)
          expect(instance).to receive(:report_heart_beat_to_azure).with(AzureHeartBeat::READY, 0, "chef-service is enabled.")

          expect(instance.run).to eq(0)
        end
      end

      context "chef-client run failed" do
        it "reports chef service enabled and chef run failed to heartbeat" do
          instance.instance_variable_set(:@chef_client_error, "Chef client failed")

          expect(instance).to receive(:load_env)
          expect(instance).to receive(:report_heart_beat_to_azure).with(AzureHeartBeat::NOTREADY, 0, "Enabling chef-service...")
          expect(instance).to receive(:enable_chef)
          expect(instance).to receive(:report_heart_beat_to_azure).with(AzureHeartBeat::READY, 0, "chef-service is enabled. Chef client run failed with error- Chef client failed")

          expect(instance.run).to eq(0)
        end
      end

      context "extended_logs is set to false" do
        before do
          allow(instance).to receive(:load_env)
          allow(instance).to receive(:report_heart_beat_to_azure)
          allow(instance).to receive(:enable_chef)
          instance.instance_variable_set(:@extended_logs, 'false')
        end

        it "does not invoke fetch_chef_client_logs method" do
          expect(instance).to_not receive(:fetch_chef_client_logs)
          instance.run
        end
      end

      context "extended_logs is set to true" do
        context "first chef-client run" do
          before do
            allow(instance).to receive(:load_env)
            allow(instance).to receive(:report_heart_beat_to_azure)
            allow(instance).to receive(:enable_chef)
            instance.instance_variable_set(:@extended_logs, 'true')
            instance.instance_variable_set(:@child_pid, 123)
          end

          it "does not invoke fetch_chef_client_logs method" do
            expect(instance).to receive(:fetch_chef_client_logs)
            instance.run
          end
        end

        context "subsequent chef-client run" do
          before do
            allow(instance).to receive(:load_env)
            allow(instance).to receive(:report_heart_beat_to_azure)
            allow(instance).to receive(:enable_chef)
            instance.instance_variable_set(:@extended_logs, 'true')
            instance.instance_variable_set(:@child_pid, nil)
          end

          it "does not invoke fetch_chef_client_logs method" do
            expect(instance).to_not receive(:fetch_chef_client_logs)
            instance.run
          end
        end
      end
    end

    context "Chef service enable failed" do
      before do
        instance.instance_variable_set(:@exit_code, 1)
      end

      context "chef-client run was successful" do
        it "reports chef service enable failure and chef run success to heartbeat" do
          expect(instance).to receive(:load_env)
          expect(instance).to receive(:report_heart_beat_to_azure).with(AzureHeartBeat::NOTREADY, 0, "Enabling chef-service...")
          expect(instance).to receive(:enable_chef)
          expect(instance).to receive(:report_heart_beat_to_azure).with(AzureHeartBeat::NOTREADY, 0, "chef-service enable failed.")

          expect(instance.run).to eq(1)
        end
      end

      context "chef-client run failed" do
        it "reports chef service enable failure and chef run failure to heartbeat" do
          instance.instance_variable_set(:@chef_client_error, "Chef client failed")

          expect(instance).to receive(:load_env)
          expect(instance).to receive(:report_heart_beat_to_azure).with(AzureHeartBeat::NOTREADY, 0, "Enabling chef-service...")
          expect(instance).to receive(:enable_chef)
          expect(instance).to receive(:report_heart_beat_to_azure).with(AzureHeartBeat::NOTREADY, 0, "chef-service enable failed. Chef client run failed with error- Chef client failed")

          expect(instance.run).to eq(1)
        end
      end
    end
  end

  context "load_env" do
    it "loads azure specific environment configurations from config file." do
      expect(instance).to receive(:read_config)
      instance.send(:load_env)
    end
  end

  context "enable_chef" do
    it "configures, installs and enables chef." do
      expect(instance).to receive(:configure_chef_only_once)
      expect(instance).to receive(:install_chef_service)
      expect(instance).to receive(:enable_chef_service)
      instance.send(:enable_chef)
    end
  end

  context "install_chef_service" do
    it "installs the chef service and returns the status to azure." do
      expect(instance).to receive(:report_status_to_azure).with("chef-service installed", "success")
      allow(ChefService).to receive_message_chain(:new, :install).and_return(0)
      instance.send(:install_chef_service)
    end

    it "installs the chef service and returns the status to azure." do
      expect(instance).to receive(:report_status_to_azure).with("chef-service install failed - ", "error")
      allow(ChefService).to receive_message_chain(:new, :install).and_return(1)
      instance.send(:install_chef_service)
    end
  end

  context "enable_chef_service" do
    it "enables the chef service and returns the status to azure." do
      expect(instance).to receive(:report_status_to_azure).with("chef-service enabled", "success")
      allow(ChefService).to receive_message_chain(:new, :enable).and_return(0)
      instance.send(:enable_chef_service)
    end

    it "enables the chef service and returns the status to azure." do
      expect(instance).to receive(:report_status_to_azure).with("chef-service enable failed - ", "error")
      allow(ChefService).to receive_message_chain(:new, :enable).and_return(1)
      instance.send(:enable_chef_service)
    end
  end

  describe "configure_chef_only_once" do
    context "first chef-client run" do
      context "extended_logs set to false" do
        before do
          allow(File).to receive(:exists?).and_return(false)
          allow(instance).to receive(:puts)
          allow(File).to receive(:open)
          @bootstrap_directory = Dir.home
          allow(instance).to receive(
            :bootstrap_directory).and_return(@bootstrap_directory)
          allow(instance).to receive(:handler_settings_file).and_return(
            mock_data("handler_settings.settings"))
          allow(instance).to receive(:get_validation_key).and_return("")
          allow(instance).to receive(:get_client_key).and_return("")
          allow(instance).to receive(:get_chef_server_ssl_cert).and_return("")
          allow(IO).to receive_message_chain(
            :read, :chomp).and_return("template")
          allow(Process).to receive(:detach)
          @sample_config = {:environment=>"_default", :chef_node_name=>"mynode3", :chef_extension_root=>"./", :user_client_rb=>"", :log_location=>nil, :chef_server_url=>"https://api.opscode.com/organizations/clochefacc", :validation_client_name=>"clochefacc-validator", :secret=>nil}
          @sample_runlist = ["recipe[getting-started]", "recipe[apt]"]
        end

        it "runs chef-client for the first time on windows" do
          allow(instance).to receive(:windows?).and_return(true)
          expect(Chef::Knife::Core::WindowsBootstrapContext).to receive(
            :new).with(@sample_config, @sample_runlist, any_args)
          allow(Erubis::Eruby).to receive(:new).and_return("template")
          expect(Erubis::Eruby.new).to receive(:evaluate)
          expect(instance).to receive(:shell_out).and_return(
            OpenStruct.new(:exitstatus => 0, :stdout => ""))
          # Call to load_cloud_attributes_in_hints method has been removed for time being
          #expect(instance).to receive(:load_cloud_attributes_in_hints)
          expect(FileUtils).to receive(:rm)
          expect(Process).to receive(:spawn).with("chef-client -c #{@bootstrap_directory}/client.rb -j #{@bootstrap_directory}/first-boot.json -E #{@sample_config[:environment]} -L #{@sample_config[:log_location]}/chef-client.log --once ").and_return(123)
          instance.send(:configure_chef_only_once)
          expect(instance.instance_variable_get(:@child_pid)).to be == 123
          expect(instance.instance_variable_get(:@chef_client_success_file)).to be nil
          expect(instance.instance_variable_get(:@chef_client_run_start_time)).to be nil
        end

        it "runs chef-client for the first time on linux" do
          allow(instance).to receive(:windows?).and_return(false)
          #expect(instance).to receive(:load_cloud_attributes_in_hints)
          expect(Chef::Knife::Core::BootstrapContext).to receive(
            :new).with(@sample_config, @sample_runlist, any_args)
          allow(Erubis::Eruby).to receive(:new).and_return("template")
          expect(Erubis::Eruby.new).to receive(:evaluate)
          expect(instance).to receive(:shell_out).and_return(
            OpenStruct.new(:exitstatus => 0, :stdout => ""))
          expect(Process).to receive(:spawn).with("chef-client -c #{@bootstrap_directory}/client.rb -j #{@bootstrap_directory}/first-boot.json -E #{@sample_config[:environment]} -L #{@sample_config[:log_location]}/chef-client.log --once ").and_return(456)
          instance.send(:configure_chef_only_once)
          expect(instance.instance_variable_get(:@child_pid)).to be == 456
          expect(instance.instance_variable_get(:@chef_client_success_file)).to be nil
          expect(instance.instance_variable_get(:@chef_client_run_start_time)).to be nil
        end
      end

      context "extended_logs set to true" do
        before do
          allow(File).to receive(:exists?).and_return(false)
          allow(instance).to receive(:puts)
          allow(File).to receive(:open)
          @bootstrap_directory = Dir.home
          allow(instance).to receive(
            :bootstrap_directory).and_return(@bootstrap_directory)
          allow(instance).to receive(:handler_settings_file).and_return(
            mock_data("handler_settings_1.settings"))
          allow(instance).to receive(:get_validation_key).and_return("")
          allow(instance).to receive(:get_client_key).and_return("")
          allow(instance).to receive(:get_chef_server_ssl_cert).and_return("")
          allow(IO).to receive_message_chain(
            :read, :chomp).and_return("template")
          allow(Process).to receive(:detach)
          @sample_config = {:environment=>"_default", :chef_node_name=>"mynode3", :chef_extension_root=>"./", :user_client_rb=>"", :log_location=>nil, :chef_server_url=>"https://api.opscode.com/organizations/clochefacc", :validation_client_name=>"clochefacc-validator", :secret=>nil}
          @sample_runlist = ["recipe[getting-started]", "recipe[apt]"]
        end

        it "runs chef-client for the first time on windows" do
          allow(instance).to receive(:windows?).and_return(true)
          expect(Chef::Knife::Core::WindowsBootstrapContext).to receive(
            :new).with(@sample_config, @sample_runlist, any_args)
          allow(Erubis::Eruby).to receive(:new).and_return("template")
          expect(Erubis::Eruby.new).to receive(:evaluate)
          expect(instance).to receive(:shell_out).and_return(
            OpenStruct.new(:exitstatus => 0, :stdout => ""))
          # Call to load_cloud_attributes_in_hints method has been removed for time being
          #expect(instance).to receive(:load_cloud_attributes_in_hints)
          expect(FileUtils).to receive(:rm)
          expect(Process).to receive(:spawn).with("chef-client -c #{@bootstrap_directory}/client.rb -j #{@bootstrap_directory}/first-boot.json -E #{@sample_config[:environment]} -L #{@sample_config[:log_location]}/chef-client.log --once  && touch c:\\chef_client_success").and_return(789)
          instance.send(:configure_chef_only_once)
          expect(instance.instance_variable_get(:@child_pid)).to be == 789
          expect(instance.instance_variable_get(:@chef_client_success_file)).to be == 'c:\\chef_client_success'
          expect(instance.instance_variable_get(:@chef_client_run_start_time)).to_not be nil
        end

        it "runs chef-client for the first time on linux" do
          allow(instance).to receive(:windows?).and_return(false)
          #expect(instance).to receive(:load_cloud_attributes_in_hints)
          expect(Chef::Knife::Core::BootstrapContext).to receive(
            :new).with(@sample_config, @sample_runlist, any_args)
          allow(Erubis::Eruby).to receive(:new).and_return("template")
          expect(Erubis::Eruby.new).to receive(:evaluate)
          expect(instance).to receive(:shell_out).and_return(
            OpenStruct.new(:exitstatus => 0, :stdout => ""))
          expect(Process).to receive(:spawn).with("chef-client -c #{@bootstrap_directory}/client.rb -j #{@bootstrap_directory}/first-boot.json -E #{@sample_config[:environment]} -L #{@sample_config[:log_location]}/chef-client.log --once  && touch /tmp/chef_client_success").and_return(120)
          instance.send(:configure_chef_only_once)
          expect(instance.instance_variable_get(:@child_pid)).to be == 120
          expect(instance.instance_variable_get(:@chef_client_success_file)).to be == '/tmp/chef_client_success'
          expect(instance.instance_variable_get(:@chef_client_run_start_time)).to_not be nil
        end
      end
    end

    context "subsequent chef_client run" do
      before do
        allow(File).to receive(:exists?).and_return(true)
      end

      it "does not spawn chef-client run process irrespective of the platform" do
        expect(Process).to_not receive(:spawn)
        expect(Process).to_not receive(:detach)
        expect(instance.instance_variable_get(:@child_pid)).to be nil
        instance.send(:configure_chef_only_once)
      end
    end
  end

  describe "chef_client_log_path" do
    context "log_location defined in chef_config read from chef config file" do
      before do
        allow(instance).to receive(:chef_config)
        chef_config = {:log_location => './logs/chef-client.log'}
        instance.instance_variable_set(:@chef_config, chef_config)
        instance.instance_variable_set(:@azure_plugin_log_location, './logs_other')
      end

      it "returns chef_client log path from chef_config log_location" do
        response = instance.send(:chef_client_log_path)
        expect(response).to be == './logs/chef-client.log'
      end
    end

    context "log_location not defined in chef config file" do
      before do
        allow(instance).to receive(:chef_config)
        chef_config = {:log_location => nil}
        instance.instance_variable_set(:@chef_config, chef_config)
        instance.instance_variable_set(:@azure_plugin_log_location, './logs_other')
      end

      it "returns chef_client log path from chef_config log_location" do
        response = instance.send(:chef_client_log_path)
        expect(response).to be == './logs_other/chef-client.log'
      end
    end


  end

  describe "fetch_chef_client_logs" do
    context "for windows" do
      before do
        instance.instance_variable_set(:@chef_extension_root, 'c:\\extension_root')
        instance.instance_variable_set(:@child_pid, 123)
        instance.instance_variable_set(:@chef_client_run_start_time, '2016-05-03 20:51:01 +0530')
        allow(instance).to receive(:chef_config).and_return(nil)
        instance.instance_variable_set(:@chef_config, {:log_location => nil})
        instance.instance_variable_set(:@azure_plugin_log_location, 'c:\\logs')
        instance.instance_variable_set(:@azure_status_file, 'c:\\extension_root\\status\\0.status')
        allow(instance).to receive(:windows?).and_return(true)
        ENV['SYSTEMDRIVE'] = 'c:'
        instance.instance_variable_set(:@chef_client_success_file, 'c:\\chef_client_success')
      end

      it "spawns chef_client run logs collection script" do
        expect(Process).to receive(:spawn).with(
          "ruby c:\\extension_root/bin/chef_client_logs.rb 123 \"2016-05-03 20:51:01 +0530\" c:\\logs/chef-client.log c:\\extension_root\\status\\0.status c:/chef c:\\chef_client_success").
            and_return(456)
        expect(Process).to receive(:detach).with(456)
        expect(instance).to receive(:puts)
        instance.send(:fetch_chef_client_logs)
      end
    end

    context "for linux" do
      before do
        instance.instance_variable_set(:@chef_extension_root, '/var/extension_root')
        instance.instance_variable_set(:@child_pid, 789)
        instance.instance_variable_set(:@chef_client_run_start_time, '2016-05-03 21:51:01 +0530')
        allow(instance).to receive(:chef_config).and_return(nil)
        instance.instance_variable_set(:@chef_config, {:log_location => nil})
        instance.instance_variable_set(:@azure_plugin_log_location, '/var/logs')
        instance.instance_variable_set(:@azure_status_file, '/var/extension_root/status/0.status')
        allow(instance).to receive(:windows?).and_return(false)
        instance.instance_variable_set(:@chef_client_success_file, '/tmp/chef_client_success')
      end

      it "spawns chef_client run logs collection script" do
        expect(Process).to receive(:spawn).with(
          "ruby /var/extension_root/bin/chef_client_logs.rb 789 \"2016-05-03 21:51:01 +0530\" /var/logs/chef-client.log /var/extension_root/status/0.status /etc/chef /tmp/chef_client_success").
            and_return(120)
        expect(Process).to receive(:detach).with(120)
        expect(instance).to receive(:puts)
        instance.send(:fetch_chef_client_logs)
      end
    end
  end

  context "load_settings" do
    it "loads the settings from the handler settings file." do
      expect(instance).to receive(:handler_settings_file).exactly(5).times
      expect(instance).to receive(:value_from_json_file).exactly(5).times
      expect(instance).to receive(:get_validation_key)
      allow(instance).to receive(:get_client_key).and_return("")
      allow(instance).to receive(:get_chef_server_ssl_cert).and_return("")
      instance.send(:load_settings)
    end
  end

  context "handler_settings_file" do
    it "returns the handler settings file when the settings file is present." do
      allow(Dir).to receive_message_chain(:glob, :sort).and_return ["test"]
      expect(File).to receive(:expand_path)
      instance.send(:handler_settings_file)
    end

    it "returns error message when the settings file is not present." do
      allow(Dir).to receive_message_chain(:glob, :sort).and_return []
      expect(File).to receive(:expand_path)
      allow(Chef::Log).to receive(:error)
      expect(instance).to receive(:report_status_to_azure)
      expect {instance.send(:handler_settings_file)}.to raise_error(
        "Configuration error. Azure chef extension Settings file missing.")
    end
  end

  context "escape_runlist" do
    it "escapes and formats the runlist." do
      instance.send(:escape_runlist, "test")
    end
  end

  context "get_validation_key on linux" , :unless => (RUBY_PLATFORM =~ /mswin|mingw|windows/) do
    it "extracts and returns the validation_key from encrypted text." do
      @object = Object.new
      allow(File).to receive(:read)
      allow(File).to receive(:exists?).and_return(true)
      allow(OpenSSL::X509::Certificate).to receive(:new)
      allow(OpenSSL::PKey::RSA).to receive(:new).and_return(@object)
      allow(Base64).to receive(:decode64)
      allow(OpenSSL::PKCS7).to receive(:new).and_return(@object)
      expect(instance).to receive(:handler_settings_file)
      expect(instance).to receive(:value_from_json_file).twice.and_return('')
      expect(@object).to receive(:decrypt)
      expect(@object).to receive(:to_pem)
      instance.send(:get_validation_key, 'encrypted_text', 'format')
    end
  end

  context "get_validation_key on windows" , :if => (RUBY_PLATFORM =~ /mswin|mingw|windows/) do
    it "extracts and returns the validation_key from encrypted text." do
      allow(File).to receive(:expand_path).and_return(".")
      allow(File).to receive(:dirname)
      allow(instance).to receive(:shell_out).and_return(OpenStruct.new(:exitstatus => 0, :stdout => ""))
      expect(instance).to receive(:handler_settings_file)
      expect(instance).to receive(:value_from_json_file).twice.and_return("")
      instance.send(:get_validation_key, "encrypted_text", "format")
    end
  end

  context "runlist is in correct format when" do
    it "accepts format: recipe[cookbook]" do
      sample_input = "recipe[abc]"
      expected_output = ["recipe[abc]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end

    it "accepts format: role[rolename]" do
      sample_input = "role[abc]"
      expected_output = ["role[abc]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end

    it "accepts format: recipe[cookbook1],recipe[cookbook2]" do
      sample_input = "recipe[cookbook1],recipe[cookbook2]"
      expected_output = ["recipe[cookbook1]","recipe[cookbook2]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end

    it "accepts format: recipe[cookbook1],role[rolename]" do
      sample_input = "recipe[cookbook1],role[rolename]"
      expected_output = ["recipe[cookbook1]","role[rolename]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end

    it "accepts format: cookbook1,cookbook2" do
      sample_input = "cookbook1,cookbook2"
      expected_output = ["recipe[cookbook1]", "recipe[cookbook2]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end

    it "accepts format: recipe[cookbook::recipe]" do
      sample_input = "recipe[cookbook::recipe]"
      expected_output = ["recipe[cookbook::recipe]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end

    it "accepts format: recipe[recipe1],recipe2" do
      sample_input = "recipe[recipe1],recipe2"
      expected_output = ["recipe[recipe1]", "recipe[recipe2]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end

    it "accepts format: role[rolename],recipe" do
      sample_input = "role[rolename],recipe"
      expected_output = ["role[rolename]", "recipe[recipe]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end

    it "parse escape character runlist" do
      sample_input = "\"role[rolename]\",\"recipe\""
      expected_output = ["role[rolename]", "recipe[recipe]"]
      escape_runlist_call = instance.send(:escape_runlist,sample_input)
      expect(escape_runlist_call).to eq(expected_output)
    end
  end

  context "load_cloud_attributes_in_hints" do
    it 'loads cloud attributs in Chef::Config["knife"]["hints"]' do
      allow(instance).to receive(Socket.gethostname).and_return("something")
      instance.send(:load_cloud_attributes_in_hints)
    end
  end
end