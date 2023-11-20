module Utilities
  def babel_random_pdb_to_pdb(input_pdb_name : String, output_pdb_name : String)
    obabel = "obabel"
    args1 = ["-i", "pdb", input_pdb_name, "-O", output_pdb_name, "-e", "--gen3D", "--medium"]
    run_cmd_silent(cmd = obabel, args = args1, output_file = Nil)
    min_lastframe = Chem::Structure.from_pdb(input_pdb_name)
    variant = Chem::Structure.from_pdb(output_pdb_name)
    index = 0
    min_lastframe['A'][1].each_atom { |atom|
      atom.coords = variant.atoms[index].coords
      atom.temperature_factor = 1.0
      index += 1
    }
    min_lastframe.to_pdb(output_pdb_name, bonds: :none)
    min_lastframe
  end

  def babel_random_mol_to_mol(input_mol : String, output_mol_name : String)
    obabel = "obabel"
    args1 = ["-i", "mol", input_mol, "-O", output_mol_name, "-e", "--gen3D", "--medium"]
    run_cmd_silent(cmd = obabel, args = args1, output_file = Nil)
    min_lastframe = Chem::Structure.from_mol(input_mol)
    variant = Chem::Structure.from_mol(output_mol_name)
    index = 0
    min_lastframe['A'][1].each_atom { |atom|
      atom.coords = variant.atoms[index].coords
      atom.temperature_factor = 1.0
      index += 1
    }
    min_lastframe.to_pdb(output_mol_name, bonds: :none)
    min_lastframe
  end

  def babel_random_mol_to_pdb(input_mol : String, output_pdb_name : String)
    obabel = "obabel"
    args1 = ["-i", "mol", input_mol, "-O", output_pdb_name, "-e", "--gen3D", "--medium"]
    run_cmd_silent(cmd = obabel, args = args1, output_file = Nil)
    min_lastframe = Chem::Structure.from_mol(input_mol)
    variant = Chem::Structure.from_pdb(output_pdb_name)
    index = 0
    min_lastframe.each_atom { |atom|
      atom.coords = variant.atoms[index].coords
      atom.temperature_factor = 1.0
      index += 1
    }
    min_lastframe.to_pdb(output_pdb_name, bonds: :none)
    min_lastframe
  end
end
