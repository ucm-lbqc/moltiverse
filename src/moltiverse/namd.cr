module NAMD::Input
  def self.minimization(output_file : String, lig : Ligand)
    if lig.explicit_water
      cell = Chem::Structure.from_pdb(lig.pdb_system).cell
      content = ECR.render "./src/moltiverse/templates/min_water.ecr"
    else
      content = ECR.render "./src/moltiverse/templates/min_vacuum.ecr"
    end
    File.write output_file, content
  end

  def self.minimization(output_file : String, lig : Conformer)
    if lig.explicit_water
      cell = Chem::Structure.from_pdb(lig.pdb_system).cell
      content = ECR.render "./src/moltiverse/templates/min_water_conformers.ecr"
    else
      content = ECR.render "./src/moltiverse/templates/min_vacuum_conformers.ecr"
    end
    File.write output_file, content
  end

  def self.enhanced_sampling(output_file : String, lig : Ligand, time : Float64)
    stem = Path[output_file].stem
    if lig.explicit_water
      content = ECR.render "./src/moltiverse/templates/eabf_rmsd_rdgyr_water.ecr"
    else
      content = ECR.render "./src/moltiverse/templates/eabf_rmsd_rdgyr_vacuum.ecr"
    end
    File.write output_file, content
  end

  def self.colvars(
    output_file : String,
    colvars : Array(Colvar),
    ref_structure : Chem::Structure,
    use_metadynamics : Bool,
    fullsamples : Int32,
    hillweight : Float64,
    hillwidth : Float64,
    newhillfrequency : Int32
  )
    unless ref_structure.source_file
      raise ArgumentError.new("#{ref_structure} do not have a path to file")
    end
    content = ECR.render "./src/moltiverse/templates/colvars.ecr"
    File.write output_file, content
  end
end

def NAMD.run(
  cfg : Path | String,
  *args,
  cores : Int = System.cpu_count,
  use_gpu : Bool = false,
  retries : Int = 1,
  **options
) : Bool
  cli_args = [cfg, "+p", cores]
  cli_args << "+devices" << 0 if use_gpu
  args.each do |value|
    cli_args << "+#{value}"
  end
  options.each do |key, value|
    next if value == false
    cli_args << "+#{key}"
    cli_args << value unless value.is_a?(Bool)
  end
  output = "#{Path[cfg].stem}.out"
  ::run "namd2", cli_args, output, retries
end
