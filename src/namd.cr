require "ecr"

module NAMD::Input
  def self.minimization(output_file : String, lig : Ligand)
    if lig.explicit_water
      cell = Chem::Structure.from_pdb(lig.pdb_system).cell
      content = ECR.render "./src/templates/min_water.ecr"
    else
      content = ECR.render "./src/templates/min_vacuum.ecr"
    end
    File.write output_file, content
  end

  def self.enhanced_sampling(output_file : String, lig : Ligand, time : Float64)
    stem = Path[output_file].stem
    if lig.explicit_water
      content = ECR.render "./src/templates/eabf_rmsd_rdgyr_water.ecr"
    else
      content = ECR.render "./src/templates/eabf_rmsd_rdgyr_vacuum.ecr"
    end
    File.write output_file, content
  end

  def self.colvars(
    output_file : String,
    colvars : Array(Colvar),
    ref_structure : Chem::Structure,
    use_metadynamics : Bool,
    fullsamples : Int32
  )
    unless ref_structure.source_file
      raise ArgumentError.new("#{ref_structure} do not have a path to file")
    end
    content = ECR.render "./src/templates/colvars.ecr"
    File.write output_file, content
  end
end
