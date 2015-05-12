require 'spec_helper_acceptance'
require 'securerandom'

shared_context 'a running vm' do
  before(:all) do
    @client = VsphereHelper.new
    @template = 'machine.pp.tmpl'
    @name = "CLOUD-#{SecureRandom.hex(8)}"
    @path = "/opdx1/vm/eng/#{@name}"
    @config = {
      :name          => @path,
      :compute       => 'general1',
      :template_path => '/eng/templates/debian-wheezy-3.2.0.4-amd64-vagrant-vmtools_9349',
      :memory        => 512,
      :cpus          => 2,
    }
    datacenter = @client.datacenter
    template = datacenter.find_vm(@config[:template_path])
    pool = datacenter.find_compute_resource(@config[:compute]).resourcePool
    relocate_spec = RbVmomi::VIM.VirtualMachineRelocateSpec(:pool => pool)
    clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(
      :location => relocate_spec,
      :powerOn => true,
      :template => false)
    clone_spec.config = RbVmomi::VIM.VirtualMachineConfigSpec(deviceChange: [])
    target_folder = datacenter.vmFolder.find('eng')
    template.CloneVM_Task(
      :folder => target_folder,
      :name => @name,
      :spec => clone_spec).wait_for_completion

    @datastore = @client.datacenter.datastore.first
    @machine = @client.get_machine(@path)
  end

  after(:all) do
    @machine = @client.get_machine(@path)
    if @machine
      @machine.PowerOffVM_Task.wait_for_completion if @machine.runtime.powerState == 'poweredOn'
      @machine.Destroy_Task.wait_for_completion
    end
  end
end

describe 'vsphere_machine' do
  describe 'should be able to unregister a machine' do
    include_context 'a running vm'

    before(:all) do
      @unregister_config = @config.dup
      @unregister_config[:ensure] = :unregistered
      PuppetManifest.new(@template, @unregister_config).apply
    end

    it 'should be removed' do
      machine = @client.get_machine(@path)
      expect(machine).to be_nil
    end

    it 'should not fail to be applied multiple times' do
      success = PuppetManifest.new(@template, @unregister_config).apply[:exit_status].success?
      expect(success).to eq(true)
    end

    it 'should keep the machine\'s vmx file around' do
      vmx = @datastore.browser.SearchDatastoreSubFolders_Task({:datastorePath => "[#{@datastore.name}] #{@name}", :searchSpec => { :matchPattern => ["#{@name}.vmx"] } }).wait_for_completion
      expect(vmx).not_to be_nil
      expect(vmx.first.file.first.path).to eq("#{@name}.vmx")
    end

    it 'should keep the machine\'s vmdk file around' do
      vmdk = @datastore.browser.SearchDatastoreSubFolders_Task({:datastorePath => "[#{@datastore.name}] #{@name}", :searchSpec => { :matchPattern => ["#{@name}_1.vmdk"] } }).wait_for_completion
      expect(vmdk).not_to be_nil
      expect(vmdk.first.file.first.path).to eq("#{@name}_1.vmdk")
    end

    context 'when looked for using puppet resource' do
      before(:all) do
        @result = TestExecutor.puppet_resource('vsphere_machine', {:name => @path}, '--modulepath ../')
      end

      it 'should not return an error' do
        expect(@result.stderr).not_to match(/\b/)
      end

      it 'should report the correct ensure value' do
        regex = /(ensure)(\s*)(=>)(\s*)('absent')/
        expect(@result.stdout).to match(regex)
      end

    end

  end

  describe 'should be able to delete a machine' do
    include_context 'a running vm'

    before(:all) do
      @absent_config = @config.dup
      @absent_config[:ensure] = :absent
      PuppetManifest.new(@template, @absent_config).apply
    end

    it 'should be removed' do
      @machine = @client.get_machine(@path)
      expect(@machine).to be_nil
    end

    it 'and should not fail to be applied multiple times' do
      success = PuppetManifest.new(@template, @absent_config).apply[:exit_status].success?
      expect(success).to eq(true)
    end

    it 'should have removed the machine\'s vmx file' do
      expect {
        @datastore.browser.SearchDatastoreSubFolders_Task({:datastorePath => "[#{@datastore.name}] #{@name}", :searchSpec => { :matchPattern => ["#{@name}.vmx"] } }).wait_for_completion
      }.to raise_error(RbVmomi::Fault, /FileNotFound/)
    end

    it 'should have removed the machine\'s vmdk file' do
      expect {
        @datastore.browser.SearchDatastoreSubFolders_Task({:datastorePath => "[#{@datastore.name}] #{@name}", :searchSpec => { :matchPattern => ["#{@name}_1.vmdk"] } }).wait_for_completion
      }.to raise_error(RbVmomi::Fault, /FileNotFound/)
    end

    context 'when looked for using puppet resource' do
      before(:all) do
        @result = TestExecutor.puppet_resource('vsphere_machine', {:name => @path}, '--modulepath ../')
      end

      it 'should not return an error' do
        expect(@result.stderr).not_to match(/\b/)
      end

      it 'should report the correct ensure value' do
        regex = /(ensure)(\s*)(=>)(\s*)('absent')/
        expect(@result.stdout).to match(regex)
      end
    end

  end
end
