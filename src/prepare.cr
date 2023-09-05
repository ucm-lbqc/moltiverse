require "./namdconf.cr"
require "ecr"
require "chem"
require "./protocols.cr"
require "./analysis.cr"
require "colorize"
require "./colors.cr"
require "./execution.cr"

include Namdconf
include Chem
include Protocols
include Analysis
include Coloring
include Execution

module Prepare
  class Ligand
    def initialize(file : String, keep_hydrogens : Bool, ph : Float32 | Float64, output_name : String, seed : Int32 | String, explicit_water : Bool, sampling_protocol : SamplingProtocol)
      unless File.exists?(file)
          STDERR.puts "Error: ligand file not found: #{file}"
          exit(1)
      end
      @file = Path.new(file).expand().to_s
      @path = Path.new(file).expand().parent()
      @extension = "#{File.extname("#{@file}")}"
      @format = "#{@extension.split(".")[1]}"
      @basename = "#{File.basename("#{@file}", "#{@extension}")}"
      @keep_hydrogens = keep_hydrogens
      @ph = ph
      @output_name = output_name
      @topology_file = "empty"
      @coordinates_file = "empty"
      @pdb_system = "empty"
      @dcd = "empty"
      @lig_center = Spatial::Vec3.new(0,0,0)
      @pdb_reference = "empty"
      @explicit_water = explicit_water
      @seed = seed
      @sampling_protocol = sampling_protocol
      @time_rmsd = sampling_protocol.time_rmsd
      @time_rdgyr = sampling_protocol.time_rdgyr
    end
    @time_rmsd : Float32
    @time_rdgyr : Float32
    def file
      @file
    end
    def keep_hydrogens
      @keep_hydrogens
    end
    def path
      @path
    end
    def extension
      @extension
    end
    def format
      @format
    end
    def ph
      @ph
    end
    def basename
      @basename
    end
    def charge
      @charge
    end
    def output_name
      @output_name
    end
    def topology_file
      @topology_file
    end
    def coordinates_file
      @coordinates_file
    end
    def pdb_system
      @pdb_system
    end
    def dcd
      @dcd
    end
    def pdb_reference
      @pdb_reference
    end
    def explicit_water
      @explicit_water
    end
    def seed
      @seed
    end
    def sampling_protocol
      @sampling_protocol
    end
    def time_rmsd
      @sampling_protocol.time_rmsd
    end
    def lig_center
      @lig_center
    end
