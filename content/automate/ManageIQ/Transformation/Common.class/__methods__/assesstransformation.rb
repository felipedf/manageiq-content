module ManageIQ
  module Automate
    module Transformation
      module Common
        class AssessTransformation
          SUPPORTED_SOURCE_EMS_TYPES = ['vmwarews'].freeze
          SUPPORTED_DESTINATION_EMS_TYPES = ['rhevm'].freeze

          def initialize(handle = $evm)
            @handle = handle
            @task = ManageIQ::Automate::Transformation::Common::Utils.task(@handle)
            @source_vm = ManageIQ::Automate::Transformation::Common::Utils.source_vm(@handle)
          end

          def virtv2v_networks
            @source_vm.hardware.nics.select { |n| n.device_type == 'ethernet' }.collect do |nic|
              source_network = nic.lan
              destination_network = @task.transformation_destination(source_network)
              raise "[#{@source_vm.name}] NIC #{nic.device_name} [#{source_network.name}] has no mapping. Aborting." if destination_network.nil?
              {
                :source      => source_network.name,
                :destination => destination_network.name,
                :mac_address => nic.address
              }
            end
          end

          def virtv2v_disks
            @source_vm.hardware.disks.select { |d| d.device_type == 'disk' }.collect do |disk|
              source_storage = disk.storage
              destination_storage = @task.transformation_destination(disk.storage)
              raise "[#{@source_vm.name}] Disk #{disk.device_name} [#{source_storage.name}] has no mapping. Aborting." if destination_storage.nil?
              {
                :path    => disk.filename,
                :size    => disk.size,
                :percent => 0,
                :weight  => disk.size.to_f / @source_vm.allocated_disk_storage.to_f * 100
              }
            end
          end

          def source_cluster
            @source_cluster ||= @source_vm.ems_cluster.tap do |cluster|
              raise "No source cluster" if cluster.nil?
            end
          end

          def source_ems
            @source_ems ||= @source_vm.ext_management_system.tap do |ems|
              raise "No source EMS" if ems.nil?
            end
          end

          def destination_cluster
            @destination_cluster ||= @task.transformation_destination(source_cluster).tap do |cluster|
              raise "No destination cluster" if cluster.nil?
            end
          end

          def destination_ems
            @destination_ems ||= destination_cluster.ext_management_system.tap do |ems|
              raise "No destination EMS" if ems.nil?
            end
          end

          def transformation_type
            raise "Unsupported source EMS type: #{source_ems.emstype}." unless SUPPORTED_SOURCE_EMS_TYPES.include?(source_ems.emstype)
            raise "Unsupported destination EMS type: #{destination_ems.emstype}." unless SUPPORTED_DESTINATION_EMS_TYPES.include?(destination_ems.emstype)
            @handle.set_state_var(:source_ems_type, source_ems.emstype)
            @handle.set_state_var(:destination_ems_type, destination_ems.emstype)
            "#{source_ems.emstype}2#{destination_ems.emstype}"
          end

          def populate_task_options
            @task.set_option(:source_ems_id, source_ems.id)
            @task.set_option(:destination_ems_id, destination_ems.id)
            @task.set_option(:virtv2v_networks, virtv2v_networks)
            @task.set_option(:virtv2v_disks, virtv2v_disks)
            @task.set_option(:transformation_type, transformation_type)
            @task.set_option(:source_vm_power_state, @source_vm.power_state)
            @task.set_option(:collapse_snapshots, true)
            @task.set_option(:power_off, true)
          end

          def populate_factory_config
            factory_config = {
              'vmtransformation_check_interval' => @handle.object['vmtransformation_check_interval'] || '15.seconds',
              'vmpoweroff_check_interval'       => @handle.object['vmpoweroff_check_interval'] || '30.seconds'
            }
            @handle.set_state_var(:factory_config, factory_config)
          end

          def main
            %w(task_options factory_config).each { |ci| send("populate_#{ci}") }
          rescue => e
            @handle.set_state_var(:ae_state_progress, 'message' => e.message)
            raise
          end
        end
      end
    end
  end
end

ManageIQ::Automate::Transformation::Common::AssessTransformation.new.main
