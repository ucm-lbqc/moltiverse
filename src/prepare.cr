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
    def initialize(file : String, smile : Bool | String, keep_hydrogens : Bool, ph : Float32 | Float64, output_name : String, random_coords : Bool, explicit_water : Bool, sampling_protocol : SamplingProtocol, working_dir : String)
      @working_dir = working_dir
      @file = Path.new(file).expand.to_s
      @extension = "#{File.extname("#{file}")}"
      @basename = "#{File.basename("#{@file}", "#{@extension}")}"
      @smile = smile
      @keep_hydrogens = keep_hydrogens
      @ph = ph
      @output_name = output_name
      @topology_file = "empty"
      @coordinates_file = "empty"
      @pdb_system = "empty"
      @dcd = "empty"
      @lig_center = Spatial::Vec3.new(0, 0, 0)
      @pdb_reference = "empty"
      @explicit_water = explicit_water
      @random_coords = random_coords
      @sampling_protocol = sampling_protocol
      @time_rmsd = sampling_protocol.time_rmsd
      @time_rdgyr = sampling_protocol.time_rdgyr
    end

    @time_rmsd : Float32
    @time_rdgyr : Float32

    def file
      @file
    end

    def smile
      @smile
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

    def random_coords
      @random_coords
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

    def working_dir
      @working_dir
    end

    def proccess_input
      Dir.cd(@working_dir)
      puts "The output folder name will be: #{@output_name}"
      if Dir.exists?("#{@output_name}")
        Dir.cd(@output_name)
      else
        puts "Creating folder #{@output_name}"
        Dir.mkdir(@output_name)
        Dir.cd(@output_name)
      end
      if @smile
        @basename = "#{@output_name}"
        obabel = "obabel"
        args1 = ["-:#{smile}", "-h", "--gen3D", "-O", "#{@basename}.mol"]
        puts "Running openbabel convertion..."
        run_cmd(cmd = obabel, args = args1, output_file = Nil, stage = "SMILE code converted to .mol format ✔".colorize(GREEN), verbose = false)
        @format = "mol"
        @extension = ".mol"
        @file = Path.new("#{@basename}#{@extension}").expand.to_s
        @charge = Chem::Structure.read(@file).formal_charge
        puts "Molecule charge: #{@charge}"
      else
        @path = Path.new(@file).expand.parent
        @format = "#{@extension.split(".")[1]}"
        @basename = "#{File.basename("#{@file}", "#{@extension}")}"
      end
    end

    def add_h
      # 1. This stage cheks if hydrogens must be preserved, if so, only convert the file to .pdb using openbabel.
      # This must be done because RDKit does not read the formal charge  correctly when, possibly, connectivities and
      # charge in the last column of atoms do not specify the atom partial charges.
      # TO:DO 1. Proper conversion to read adecuately the formal charge. Extremely important for tleap parameterization.
      # TO:DO 2. Test antechamber to use as input the mol2 file. Require a formal charge especification?
      # TO:DO 3. If keep_hydrogens == yes and input file is a PDB, ask the user to specify the formal charge, and use it for
      # tleap parameterization.
      if @keep_hydrogens
        File.copy("#{@file}", "original_keep_hydrogens#{extension}")
        obabel = "obabel"
        args1 = ["-i", "#{@format}", "#{@file}", "-O", "#{@basename}.mol"]
        puts "Running openbabel convertion..."
        run_cmd(cmd = obabel, args = args1, output_file = Nil, stage = "File converted to .mol format ✔".colorize(GREEN), verbose = false)
        @basename = "#{@basename}"
        @format = "mol"
        @extension = ".mol"
      else
        File.copy("#{@file}", "original_no-keep_hydrogens#{extension}")
        obabel = "obabel"
        args1 = ["-i", "#{@format}", "#{@file}", "-O", "#{@basename}_h.mol", "-p", "#{@ph}"]
        puts "Running openbabel convertion..."
        run_cmd(cmd = obabel, args = args1, output_file = Nil, stage = "Hydrogen addition ✔".colorize(GREEN), verbose = false)
        @basename = "#{@basename}_h"
        @format = "mol"
        @extension = ".mol"
      end
      new_file = "#{@basename}#{@extension}"
      @file = Path.new(new_file).expand.to_s
      @path = Path.new(new_file).expand.parent
      @charge = Chem::Structure.read(@file).formal_charge
      puts "Molecule charge: #{@charge}"
    end

    def randomize_structure
      if random_coords
        obabel = "obabel"
        args1 = ["-i", "#{@format}", "#{@file}", "-o", "mol", "-O", "#{@basename}_rand.mol", "-e", "--gen3D", "--medium"]
        puts "Running openbabel structure randomization..."
        run_cmd(cmd = obabel, args = args1, output_file = Nil, stage = "Structure randomization ✔".colorize(GREEN), verbose = false)
        @extension = ".mol"
        @basename = "#{@basename}_rand"
        @format = "mol"
      end
    end

    def parameterize
      outfile = "rdkit_leap.py"
      # Convert "water" variable to yes or no for python.
      water = @explicit_water ? "yes" : "no"
      basename = @basename
      jump = "\\n"
      File.write outfile, <<-SCRIPT
      from rdkit import Chem
      from rdkit.Chem import AllChem
      #import parmed as pmd
      import subprocess
      import os
      import shutil
      if "#{@random_coords}" == "no":
        random_coords = False
      else:
        random_coords = int("#{@random_coords}")
      water = "#{water}"
    
      def run_silent(command, basename):
        with open(os.devnull, 'w')  as FNULL:
                try:
                    subprocess.run(command, shell=True, stdout=FNULL)
                except subprocess.CalledProcessError:
                    print(f"Error occured with system {basename}")
    
      #starting = Chem.rdmolfiles.MolFromMol2File(
      #          f"#{basename}.mol2", sanitize=True, removeHs=False)
      starting = Chem.rdmolfiles.MolFromPDBFile(
                f"#{basename}.pdb", sanitize=True, removeHs=False)
      # Write properties
      natoms = Chem.rdchem.Mol.GetNumAtoms(starting)
      nrot = Chem.rdMolDescriptors.CalcNumRotatableBonds(starting)
      nbonds = starting.GetNumBonds()
      charge = Chem.GetFormalCharge(starting)
      print("Ligand structure:", "#{basename}.pdb")
      print("Atoms : ", natoms)
      print("Bonds : ", nbonds)
      print("Rbonds: ", nrot)
      print("Charge: ", charge)
      if random_coords:
        # Generating random conformer from smiles:
        print("Generating random conformer from smiles code:")
        smiles = Chem.MolToSmiles(starting, allHsExplicit=True)
        print(smiles)
        ps = Chem.SmilesParserParams()
        ps.removeHs = False
        new = Chem.MolFromSmiles(smiles,ps)
        AllChem.EmbedMolecule(new, Seed=random_coords)
        print("Data generated from smiles code:")
        smiles_natoms = Chem.rdchem.Mol.GetNumAtoms(new)
        smiles_nrot = Chem.rdMolDescriptors.CalcNumRotatableBonds(new)
        smiles_nbonds = new.GetNumBonds()
        smiles_charge = Chem.GetFormalCharge(new)
        print("Random coords : ", random_coords)
        print("Atoms : ", smiles_natoms)
        print("Bonds : ", smiles_nbonds)
        print("Rbonds: ", smiles_nrot)
        print("Charge: ", smiles_charge)
        if natoms != smiles_natoms:
           print("Number of atoms differs between the original structure and the random structure generated with RDkit. Check your structure.")
           exit(1)
        elif nbonds != smiles_nbonds:
          print("Number of bonds differs between the original structure and the random structure generated with RDkit. Check your structure.")
          exit(1)
        elif nrot != smiles_nrot:
          print("Number of rotable bonds differs between the original structure and the random structure generated with RDkit. Check your structure.")
          exit(1)
        elif charge != smiles_charge:
          print("Formal charge differs between the original structure and the random structure generated with RDkit. Check your structure.")
          exit(1)
        Chem.rdmolfiles.MolToPDBFile(new, "#{basename}.pdb")
        print("Successful random generation.")
      else:
        Chem.rdmolfiles.MolToPDBFile(starting, "#{basename}.pdb")
        print("Original coordinates were preserved.")
      # Connectivity info must be erased previous to leap, if not, it will fail.
      # TO:DO Don´t write connectivity info (use chem.cr)
      with open("#{basename}.pdb", "r") as input:
        with open("temp.txt", "w") as output:
          # iterate all lines from file
          for line in input:
            if not line.strip("\\n").startswith('CONECT'):
              output.write(line)
      # replace file with original name
      shutil.copy('temp.txt', '#{basename}.pdb')
      #print("Running leap...")
      with open('run_leap.sh', 'w') as f:
          f.write(f'ligand="#{basename[0...3]}"' + '#{jump}')
          f.write(f'pdb="#{basename}"' + '#{jump}')
          f.write(f'charge="{charge}"' + '#{jump}')
          f.write(
              f'antechamber -i $pdb.pdb -fi pdb -o $ligand.mol2 -fo mol2 -c bcc -nc $charge -rn $ligand -at gaff2' + '#{jump}')
          f.write(
              f'parmchk2 -i $ligand.mol2 -f mol2 -o $ligand.frcmod -s gaff2' + '#{jump}')
          f.write('cat > tleap1.in <<- EOS' + '#{jump}')
          f.write('source leaprc.gaff2' + '#{jump}')
          f.write('LIG = loadmol2 ${ligand}.mol2' + '#{jump}')
          f.write('loadamberparams ${ligand}.frcmod' + '#{jump}')
          f.write('saveAmberParm LIG ${pdb}.prmtop ${pdb}.inpcrd' + '#{jump}')
          f.write('savePdb LIG ${pdb}.pdb' + '#{jump}')
          f.write('quit' + '#{jump}')
          f.write('EOS' + '#{jump}')
          f.write('tleap -s -f tleap1.in > ${ligand}_tleap1.out' + '#{jump}')
          if water == "yes":
            f.write('cat > tleap2.in <<- EOS' + '#{jump}')
            f.write('source leaprc.gaff2' + '#{jump}')
            f.write('source leaprc.water.tip3p' + '#{jump}')
            f.write('LIG = loadmol2 ${ligand}.mol2' + '#{jump}')
            f.write('solvatebox LIG SPCBOX 20 iso' + '#{jump}')
            f.write('loadamberparams ${ligand}.frcmod' + '#{jump}')
            f.write('saveAmberParm LIG ${pdb}_solv.prmtop ${pdb}_solv.inpcrd' + '#{jump}')
            f.write('savePdb LIG ${pdb}_solv.pdb' + '#{jump}')
            f.write('quit' + '#{jump}')
            f.write('EOS' + '#{jump}')
            f.write('tleap -s -f tleap2.in > ${ligand}_tleap2.out' + '#{jump}')
      os.chmod("run_leap.sh", 0o777)
      cmd = f"./run_leap.sh"
      run_silent(cmd, "Running Leap")
      #print("Running ParmEd...")
      ## Parmed format file conversion single ligand
      #amber_ligand = pmd.load_file('#{basename}.prmtop', xyz='#{basename}.inpcrd')
      #amber_ligand.save('#{basename}.psf', overwrite=True)
      #amber_ligand.save('#{basename}.top', overwrite=True)
      #amber_ligand.save('#{basename}.gro', overwrite=True)
      #amber_ligand.save('#{basename}.pqr', overwrite=True)
      
      SCRIPT
      parmed_exec = "python"
      arguments = ["rdkit_leap.py"]
      puts "Parameterizing ligand with tleap ..."
      run_cmd(cmd=parmed_exec, args=arguments, output_file=Nil, stage="parameterization", verbose=true)
      # TO:DO Check if the antechamber - leap process was successful.
      if water == "no"
        top_file = "#{@basename}.prmtop"
        coord_file = "#{@basename}.inpcrd"
        if File.exists?(top_file)
          @topology_file = Path.new(top_file).expand.to_s
        else
          puts "Topology file was not generated. Check the *.out log files."
          exit
        end
        if File.exists?(coord_file)
          @coordinates_file = Path.new(coord_file).expand.to_s
        else
          puts "Coordinates file was not generated. Check the *.out log files."
          exit
        end
        @basename = "#{@basename}"
        @pdb_system = "#{@basename}.pdb"
        puts "SYSTEM INFO: ".colorize(PURPLE), Chem::Structure.from_pdb(@pdb_system)
      end
      if water == "yes"
        top_file = "#{@basename}_solv.prmtop"
        coord_file = "#{@basename}_solv.inpcrd"
        @pdb_system = "#{@basename}_solv.pdb"
        if File.exists?(top_file)
          @topology_file = Path.new(top_file).expand.to_s
        else
          puts "Topology file was not generated. Check the *.out log files."
          exit
        end
        if File.exists?(coord_file)
          @coordinates_file = Path.new(coord_file).expand.to_s
        else
          puts "Coordinates file was not generated. Check the *.out log files."
          exit
        end
        @basename = "#{@basename}_solv"
        puts "SYSTEM INFO: ", Chem::Structure.from_pdb(pdb_system)
      end
    end

    def minimize
      pdb = Chem::Structure.from_pdb(@pdb_system)
      a, b, c = pdb.cell?.try(&.size) || {0, 0, 0}
      cx = pdb.coords.center.x
      cy = pdb.coords.center.y
      cz = pdb.coords.center.z
      minimization(@explicit_water, @basename, @topology_file, @coordinates_file, "min.namd", a, b, c, cx, cy, cz)
      namd_exec = "namd2"
      arguments = ["min.namd", "+p", "4"]
      puts "Runnning minimization..."
      run_cmd(cmd=namd_exec, args=arguments, output_file="min.out", stage="minimization", verbose=true)
      @basename = "min.#{@basename}"
      new_dcd = "#{@basename}.dcd"
      @dcd = Path.new(new_dcd).expand.to_s
      # Write last-frame of the minimization as a reference input for next calculation.
      pdb = Chem::Structure.from_pdb(@pdb_system)
      Chem::DCD::Reader.open((@dcd), pdb) do |reader|
        n_frames = reader.n_entries - 1
        lastframe = reader.read_entry n_frames
        # puts "n frames = #{reader.n_entries}"
        # Ligand geometrical center
        @lig_center = lastframe['A'][1].coords.center
        lastframe['A'][1].each_atom {|atom|
          atom.temperature_factor = 1.0}
        lastframe.to_pdb "min.lastframe.pdb"
      end
      @pdb_reference = Path.new("min.lastframe.pdb").expand.to_s
    end

    def sampling
      # Print protocol description
      puts sampling_protocol.describe
      sampling_protocol.execute(self)
    end
  end
end
