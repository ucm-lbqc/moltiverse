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
    def add_h
      puts "The output folder name will be: #{@output_name}"
      if Dir.exists?("#{@output_name}")
        Dir.cd(@output_name)
      else
        puts "Creating folder #{@output_name}"
        Dir.mkdir(@output_name)
        Dir.cd(@output_name)
      end
      # 1. This stage cheks if hydrogens must be preserved, if so, only convert the file to .pdb using openbabel.
      # This must be done because RDKit does not read the formal charge  correctly when, possibly, connectivities and
      # charge in the last column of atoms do not specify the atom partial charges.
      # TO:DO 1. Proper conversion to read adecuately the formal charge. Extremely important for tleap parameterization.
      # TO:DO 2. Test antechamber to use as input the mol2 file. Require a formal charge especification?
      # TO:DO 3. If keep_hydrogens == yes and input file is a PDB, ask the user to specify the formal charge, and use it for
      # tleap parameterization. 
      if @keep_hydrogens
        obabel = "obabel"
        args1 = ["-i", "#{@format}", "#{@file}", "-O", "#{@basename}.pdb",]
        puts "Running openbabel convertion..."
        run_cmd(cmd=obabel, args=args1, output_file=Nil, stage="converting to pdb with connectivities", verbose=true)
        puts "Converted"
        @basename = "#{@basename}"
        @format = "pdb"
        @extension = ".pdb"
        File.copy("#{basename}#{extension}", "original_keep_hydrogens#{extension}")
      else
        obabel = "obabel"
        args1 = ["-i", "#{@format}", "#{@file}", "-O", "#{@basename}_h.pdb", "-p", "#{@ph}"]
        puts "Running openbabel convertion..."
        run_cmd(cmd=obabel, args=args1, output_file=Nil, stage="hydrogen addition", verbose=true)
        puts "Converted"
        @basename = "#{@basename}_h"
        @format = "pdb"
        @extension = ".pdb"
        File.copy("#{@basename}.pdb", "original_no-keep_hydrogens#{extension}")
      end

      new_file = "#{@basename}#{@extension}"
      @file = Path.new(new_file).expand().to_s
      @path = Path.new(new_file).expand().parent()
      # TO:DO Add a proper convertion from other formats. mol, mol2, sdf, when the --keep_hydrogens = true options is used.
      #begin
      #  @charge = Chem::Structure.from_pdb(@file).formal_charge()
      #  puts "charge chem.cr: #{@charge}"
      #rescue exception
      #    puts "File #{@file} could not be read. If the option --keep_hydrogens = true, make sure that the original file is a PDB.".colorize(RED)
      #  exit
      #end
    end
