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
    def enhanced_sampling(explicit_water : Bool, system : String, topology_file : String, coordinates_file : String, output_file : String, time : Float32, window : String, type : String)
        if explicit_water
            content = ECR.render "./src/templates/eabf_rmsd_rdgyr_water.ecr"
        else
            content = ECR.render "./src/templates/eabf_rmsd_rdgyr_vacuum.ecr"
        end
        File.write output_file, content
    end
    def colvars(wtm : Bool, lw_rmsd : Float32 | Bool, up_rmsd : Float32 | Bool, lw_rdgyr : Float32 | Bool, up_rdgyr : Float32 | Bool, rmsd_active : Bool, rdgyr_active : Bool, pdb_reference : String, lig_center_x : Float64, lig_center_y : Float64, lig_center_z : Float64, output_file : String)
        content = ECR.render "./src/templates/colvars.ecr"
        File.write output_file, content
    end
end

