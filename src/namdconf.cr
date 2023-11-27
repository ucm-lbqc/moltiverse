require "ecr"
require "./protocols.cr"

module Namdconf
  def minimization(explicit_water : Bool, system : String, topology_file : String, coordinates_file : String, output_file : String, a : Float64 | Int32, b : Float64 | Int32, c : Float64 | Int32, cx : Float64, cy : Float64, cz : Float64)
    if explicit_water
      content = ECR.render "./src/templates/min_water.ecr"
    else
      content = ECR.render "./src/templates/min_vacuum.ecr"
    end
    File.write output_file, content
  end

  def enhanced_sampling(explicit_water : Bool, system : String, topology_file : String, coordinates_file : String, output_file : String, time : Float64, window : String, variant : String, type : String, output_frequency : Int32)
    if explicit_water
      content = ECR.render "./src/templates/eabf_rmsd_rdgyr_water.ecr"
    else
      content = ECR.render "./src/templates/eabf_rmsd_rdgyr_vacuum.ecr"
    end
    File.write output_file, content
  end

  def colvars(wtm : Bool, colvars : Array(Colvar), ref_structure : Chem::Structure, output_file : String, fullsamples : Int32, bin_width : Float64)
    unless ref_structure.source_file
      raise ArgumentError.new("#{ref_structure} do not have a path to file")
    end
    content = ECR.render "./src/templates/colvars.ecr"
    File.write output_file, content
  end
end
